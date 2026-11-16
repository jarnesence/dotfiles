#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/input/trackpad/TrackpadGestures.hpp>
#include <hyprland/src/managers/input/trackpad/gestures/ITrackpadGesture.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <vector>

inline HANDLE PHANDLE = nullptr;

namespace {

    using RenderWindowFn = void (*)(void*, Render::CRenderContext&, PHLWINDOW, PHLMONITOR, const Render::SWindowRenderPresentation&, const Time::steady_tp&, bool,
                                    Render::eRenderPassMode, bool, bool);

    struct SShowDesktopState {
        bool                              gesturing       = false;
        bool                              animating       = false;
        bool                              desktopShown    = false;
        float                             currentProgress = 0.0F; // 0.0 = normal, 1.0 = scattered
        float                             targetProgress  = 0.0F;
        PHLMONITORREF                     activeMonitor;
        std::chrono::steady_clock::time_point lastTick = std::chrono::steady_clock::now();

        CFunctionHook*                    renderWindowHook = nullptr;
        CHyprSignalListener               tickListener;
        CHyprSignalListener               configReloadListener;
        CHyprSignalListener               windowOpenListener;
        CHyprSignalListener               workspaceChangeListener;
    } g_state;

    // Deterministic diagonal/radial explosion offset so every window bursts toward
    // the screen corners/edges and leaves `PEEK` pixels of its corner visible.
    Vector2D computeScatterOffset(const Vector2D& winPos, const Vector2D& winSize, const Vector2D& monPos, const Vector2D& monSize, size_t idx) {
        const Vector2D monCenter = monPos + monSize * 0.5;
        const Vector2D winCenter = winPos + winSize * 0.5;

        Vector2D       delta = winCenter - monCenter;
        const double   len   = std::hypot(delta.x, delta.y);

        Vector2D       dir;
        if (len < 6.0) {
            static constexpr double corners[4][2] = {{0.75, -0.66}, {-0.75, -0.66}, {0.75, 0.66}, {-0.75, 0.66}};
            dir = Vector2D{corners[idx % 4][0], corners[idx % 4][1]};
        } else {
            dir = Vector2D{delta.x / len, delta.y / len};
            if (std::abs(dir.y) < 0.35) {
                dir.y          = (idx % 2 == 0) ? -0.55 : 0.55;
                const double n = std::hypot(dir.x, dir.y);
                dir.x /= n;
                dir.y /= n;
            } else if (std::abs(dir.x) < 0.35) {
                dir.x          = (idx % 2 == 0) ? -0.55 : 0.55;
                const double n = std::hypot(dir.x, dir.y);
                dir.x /= n;
                dir.y /= n;
            }
        }

        // Leave 25px of each window's corner/edge visible when fully scattered
        constexpr double PEEK       = 25.0;
        const double     leftEdge   = monPos.x + PEEK;
        const double     rightEdge  = monPos.x + monSize.x - PEEK;
        const double     topEdge    = monPos.y + PEEK;
        const double     bottomEdge = monPos.y + monSize.y - PEEK;

        double           tx = 1e9;
        double           ty = 1e9;

        if (dir.x > 1e-4)
            tx = (rightEdge - winPos.x) / dir.x;
        else if (dir.x < -1e-4)
            tx = (leftEdge - (winPos.x + winSize.x)) / dir.x;

        if (dir.y > 1e-4)
            ty = (bottomEdge - winPos.y) / dir.y;
        else if (dir.y < -1e-4)
            ty = (topEdge - (winPos.y + winSize.y)) / dir.y;

        const double dist = std::max(0.0, std::min(tx, ty));
        return Vector2D{dir.x * dist, dir.y * dist};
    }

    size_t windowIndexOnMonitor(const PHLWINDOW& target, const PHLMONITOR& pMonitor) {
        size_t idx = 0;
        for (const auto& w : Desktop::windowState()->windows()) {
            if (!w || !w->mapped() || w->isHidden())
                continue;
            if (w == target)
                return idx;
            if (w->m_workspace == pMonitor->m_activeWorkspace ||
                ((w->m_state & Desktop::View::WINDOW_STATE_PINNED) != Desktop::View::WINDOW_STATE_NONE && w->m_monitor == pMonitor)) {
                ++idx;
            }
        }
        return idx;
    }

    void damageActiveMonitor() {
        if (const auto mon = g_state.activeMonitor.lock())
            g_pHyprRenderer->damageMonitor(mon);
        else if (const auto cur = Desktop::focusState()->monitor())
            g_pHyprRenderer->damageMonitor(cur);
    }

    void startAnimationTo(bool showDesktop) {
        g_state.desktopShown   = showDesktop;
        g_state.targetProgress = showDesktop ? 1.0F : 0.0F;
        g_state.animating      = true;
        g_state.lastTick       = std::chrono::steady_clock::now();
        damageActiveMonitor();
    }

    void restoreIfShown() {
        if (!g_state.desktopShown && !g_state.gesturing && g_state.currentProgress <= 0.001F)
            return;

        g_state.gesturing = false;
        startAnimationTo(false);
    }

    void hkRenderWindow(void* thisptr, Render::CRenderContext& ctx, PHLWINDOW pWindow, PHLMONITOR pMonitor, const Render::SWindowRenderPresentation& presentation,
                        const Time::steady_tp& now, bool allowDim, Render::eRenderPassMode mode, bool ignorePosition, bool standalone) {
        const auto origFn = reinterpret_cast<RenderWindowFn>(g_state.renderWindowHook->m_original);

        if (g_state.currentProgress > 0.0005F && pWindow && pMonitor && pWindow->mapped() && !pWindow->isHidden()) {
            const auto targetMon = g_state.activeMonitor.lock();
            if (!targetMon || targetMon == pMonitor) {
                const bool onActiveWS    = (pWindow->m_workspace == pMonitor->m_activeWorkspace);
                const bool isPinnedOnMon = ((pWindow->m_state & Desktop::View::WINDOW_STATE_PINNED) != Desktop::View::WINDOW_STATE_NONE && pWindow->m_monitor == pMonitor);

                if (onActiveWS || isPinnedOnMon) {
                    const Vector2D winPos  = pWindow->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
                    const Vector2D winSize = pWindow->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
                    const size_t   idx     = windowIndexOnMonitor(pWindow, pMonitor);
                    const Vector2D offset  = computeScatterOffset(winPos, winSize, pMonitor->m_position, pMonitor->m_size, idx);

                    Render::SWindowRenderPresentation modPres = presentation;
                    modPres.floatingOffset += offset * static_cast<double>(g_state.currentProgress);
                    origFn(thisptr, ctx, pWindow, pMonitor, modPres, now, allowDim, mode, ignorePosition, standalone);
                    return;
                }
            }
        }

        origFn(thisptr, ctx, pWindow, pMonitor, presentation, now, allowDim, mode, ignorePosition, standalone);
    }

    class CShowDesktopGesture final : public ITrackpadGesture {
      public:
        void begin(const STrackpadGestureBegin& e) override {
            ITrackpadGesture::begin(e);
            g_state.gesturing     = true;
            g_state.animating     = false;
            g_state.activeMonitor = Desktop::focusState()->monitor();

            m_startShown    = g_state.desktopShown;
            m_startProgress = g_state.currentProgress;
            m_startScale    = e.pinch ? static_cast<float>(e.pinch->scale) : e.scale;
            if (m_startScale <= 0.01F)
                m_startScale = 1.0F;
        }

        void update(const STrackpadGestureUpdate& e) override {
            const float rawScale = e.pinch ? static_cast<float>(e.pinch->scale) : e.scale;
            const float relScale = std::max(0.1F, rawScale / m_startScale);

            // Symmetric log2 mapping with strict [0.0, 1.0] peak clamping + instant re-anchoring
            // so windows never overshoot inward/outward and reverse immediately with zero dead-zone.
            const float deltaP = std::log2(relScale) * 1.45F;
            const float rawP   = m_startProgress + deltaP;

            if (rawP > 1.0F) {
                g_state.currentProgress = 1.0F;
                m_startProgress         = 1.0F;
                m_startScale            = std::max(0.01F, rawScale);
            } else if (rawP < 0.0F) {
                g_state.currentProgress = 0.0F;
                m_startProgress         = 0.0F;
                m_startScale            = std::max(0.01F, rawScale);
            } else {
                g_state.currentProgress = rawP;
            }

            damageActiveMonitor();
        }

        void end(const STrackpadGestureEnd& e) override {
            g_state.gesturing    = false;
            const bool cancelled = e.pinch && e.pinch->cancelled;

            if (cancelled) {
                startAnimationTo(m_startShown);
                return;
            }

            if (!m_startShown) {
                startAnimationTo(g_state.currentProgress > 0.25F);
            } else {
                startAnimationTo(g_state.currentProgress > 0.75F);
            }
        }

      private:
        bool  m_startShown    = false;
        float m_startProgress = 0.0F;
        float m_startScale    = 1.0F;
    };

    void registerShowDesktopGesture() {
        (void)g_pTrackpadGestures->addGesture(makeUnique<CShowDesktopGesture>(), 4, TRACKPAD_GESTURE_DIR_PINCH, Input::HL_MODIFIER_NONE, 1.0F, false);
    }

    SDispatchResult dispatchShowDesktop(std::string args) {
        g_state.activeMonitor = Desktop::focusState()->monitor();
        startAnimationTo(!g_state.desktopShown);
        return {};
    }

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[hypr-showdesktop] Hyprland sürüm uyuşmazlığı!", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("Version mismatch");
    }

    const auto matches = HyprlandAPI::findFunctionsByName(PHANDLE, "renderWindow");
    if (matches.empty()) {
        HyprlandAPI::addNotification(PHANDLE, "[hypr-showdesktop] renderWindow bulunamadı!", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("renderWindow not found");
    }

    g_state.renderWindowHook = HyprlandAPI::createFunctionHook(PHANDLE, matches[0].address, reinterpret_cast<void*>(&hkRenderWindow));
    if (!g_state.renderWindowHook || !g_state.renderWindowHook->hook()) {
        HyprlandAPI::addNotification(PHANDLE, "[hypr-showdesktop] renderWindow hook kurulamadı!", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("Failed to hook renderWindow");
    }

    registerShowDesktopGesture();
    HyprlandAPI::addDispatcherV2(PHANDLE, "showdesktop", dispatchShowDesktop);

    g_state.tickListener = Event::bus()->m_events.tick.listen([]() {
        if (!g_state.animating)
            return;

        const auto  now = std::chrono::steady_clock::now();
        const float dt  = std::clamp(std::chrono::duration<float>(now - g_state.lastTick).count(), 0.0005F, 0.05F);
        g_state.lastTick = now;

        // Exponential spring-out curve (snappy, macOS-like deceleration)
        constexpr float SPEED = 16.0F;
        const float     alpha = 1.0F - std::exp(-SPEED * dt);
        g_state.currentProgress += (g_state.targetProgress - g_state.currentProgress) * alpha;

        if (std::abs(g_state.targetProgress - g_state.currentProgress) < 0.0015F) {
            g_state.currentProgress = g_state.targetProgress;
            g_state.animating       = false;
        }

        damageActiveMonitor();
    });

    g_state.configReloadListener = Event::bus()->m_events.config.reloaded.listen([]() {
        registerShowDesktopGesture();
    });

    g_state.windowOpenListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW) {
        restoreIfShown();
    });

    g_state.workspaceChangeListener = Event::bus()->m_events.workspace.active.listen([](PHLWORKSPACE) {
        restoreIfShown();
    });

    return {"hypr-showdesktop", "macOS-style 1:1 4-finger pinch Show Desktop", "jarn", "2.0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_state.animating       = false;
    g_state.gesturing       = false;
    g_state.desktopShown    = false;
    g_state.currentProgress = 0.0F;
    damageActiveMonitor();

    (void)g_pTrackpadGestures->removeGesture(4, TRACKPAD_GESTURE_DIR_PINCH, Input::HL_MODIFIER_NONE, 1.0F, false);
    g_state.tickListener.reset();
    g_state.configReloadListener.reset();
    g_state.windowOpenListener.reset();
    g_state.workspaceChangeListener.reset();

    if (g_state.renderWindowHook) {
        HyprlandAPI::removeFunctionHook(PHANDLE, g_state.renderWindowHook);
        g_state.renderWindowHook = nullptr;
    }
}
