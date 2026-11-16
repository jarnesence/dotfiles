#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

inline HANDLE PHANDLE = nullptr;

namespace {

    using RenderWindowFn = void (*)(void*, Render::CRenderContext&, PHLWINDOW, PHLMONITOR, const Render::SWindowRenderPresentation&, const Time::steady_tp&, bool,
                                    Render::eRenderPassMode, bool, bool);

    enum eGestureMode : uint8_t {
        MODE_NONE = 0,
        MODE_UNDECIDED,
        MODE_SHOW_DESKTOP,
        MODE_LAUNCHPAD,
    };

    struct SShowDesktopState {
        bool                                  gesturing       = false;
        bool                                  animating       = false;
        bool                                  lpAnimating     = false;
        bool                                  desktopShown    = false;
        eGestureMode                          gestureMode     = MODE_NONE;
        bool                                  startShown      = false;
        float                                 startProgress   = 0.0F;
        float                                 startScale      = 1.0F;
        float                                 currentProgress = 0.0F; // Show Desktop: 0.0 = normal, 1.0 = scattered
        float                                 targetProgress  = 0.0F;
        float                                 lpProgress      = 0.0F; // Launchpad: 0.0 = closed, 1.0 = open
        float                                 lpTarget        = 0.0F;
        float                                 lastSentLp      = -1.0F;
        bool                                  blurSaved       = false;
        std::string                           savedBlurEnabled;
        std::string                           savedBlurSize;
        std::string                           savedBlurPasses;
        int                                   lastBlurSize    = -1;
        int                                   lpSockFd        = -1;
        std::string                           lpSockPath;
        std::string                           lpStatePath;
        std::string                           sdEnabledPath;
        std::string                           lpEnabledPath;
        PHLMONITORREF                         activeMonitor;
        std::chrono::steady_clock::time_point lastTick = std::chrono::steady_clock::now();

        CFunctionHook*                        renderWindowHook = nullptr;
        CHyprSignalListener                   pinchBeginListener;
        CHyprSignalListener                   pinchUpdateListener;
        CHyprSignalListener                   pinchEndListener;
        CHyprSignalListener                   renderPreListener;
        CHyprSignalListener                   renderStageListener;
        CHyprSignalListener                   windowOpenListener;
        CHyprSignalListener                   workspaceChangeListener;
    } g_state;

    void initLaunchpadIPC() {
        const char* xdg  = std::getenv("XDG_RUNTIME_DIR");
        const char* home = std::getenv("HOME");
        std::string dir  = xdg ? std::string{xdg} : ("/run/user/" + std::to_string(getuid()));
        std::string hdir = home ? std::string{home} : "";
        g_state.lpSockPath    = dir + "/hypr-launchpad.sock";
        g_state.lpStatePath   = dir + "/hypr-launchpad.state";
        g_state.sdEnabledPath = hdir.empty() ? "" : (hdir + "/.config/hypr/showdesktop.enabled");
        g_state.lpEnabledPath = hdir.empty() ? "" : (hdir + "/.config/hypr/launchpad.enabled");
        g_state.lpSockFd      = socket(AF_UNIX, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    }

    bool readFlagFile(const std::string& path) {
        if (path.empty())
            return false;
        FILE* f = std::fopen(path.c_str(), "r");
        if (!f)
            return false;
        int ch = std::fgetc(f);
        std::fclose(f);
        return ch == '1';
    }

    bool isLaunchpadOpen() {
        return readFlagFile(g_state.lpStatePath);
    }

    bool isShowDesktopEnabled() {
        return readFlagFile(g_state.sdEnabledPath);
    }

    bool isLaunchpadEnabled() {
        return readFlagFile(g_state.lpEnabledPath);
    }

    void sendLaunchpadCmd(const std::string& cmd) {
        if (g_state.lpSockFd < 0 || g_state.lpSockPath.empty())
            return;
        sockaddr_un addr{};
        addr.sun_family = AF_UNIX;
        if (g_state.lpSockPath.size() >= sizeof(addr.sun_path))
            return;
        std::strncpy(addr.sun_path, g_state.lpSockPath.c_str(), sizeof(addr.sun_path) - 1);
        (void)sendto(g_state.lpSockFd, cmd.data(), cmd.size(), MSG_DONTWAIT, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr));
    }

    void sendLaunchpadProgressThrottled(float p, bool force = false) {
        if (!force && std::abs(p - g_state.lastSentLp) < 0.025F)
            return;
        g_state.lastSentLp = p;
        char buf[32];
        std::snprintf(buf, sizeof(buf), "p %.3f", p);
        sendLaunchpadCmd(buf);
    }

    std::string parseOptionVal(const std::string& optOut, const std::string& prefix) {
        const auto pos = optOut.find(prefix);
        if (pos == std::string::npos)
            return "";
        const auto start = pos + prefix.size();
        const auto end   = optOut.find('\n', start);
        return optOut.substr(start, end == std::string::npos ? std::string::npos : end - start);
    }

    void updateLaunchpadBlur(float p) {
        if (p > 0.02F) {
            if (!g_state.blurSaved) {
                g_state.savedBlurEnabled = parseOptionVal(HyprlandAPI::invokeHyprctlCommand("getoption", "decoration:blur:enabled"), "bool: ");
                g_state.savedBlurSize    = parseOptionVal(HyprlandAPI::invokeHyprctlCommand("getoption", "decoration:blur:size"), "int: ");
                g_state.savedBlurPasses  = parseOptionVal(HyprlandAPI::invokeHyprctlCommand("getoption", "decoration:blur:passes"), "int: ");
                g_state.blurSaved        = true;
                g_state.lastBlurSize     = -1;
                HyprlandAPI::invokeHyprctlCommand("keyword", "decoration:blur:enabled true");
                HyprlandAPI::invokeHyprctlCommand("keyword", "decoration:blur:passes 2");
            }
            const int sz = std::clamp(static_cast<int>(std::round(p * 8.0F)), 1, 8);
            if (sz != g_state.lastBlurSize) {
                g_state.lastBlurSize = sz;
                HyprlandAPI::invokeHyprctlCommand("keyword", "decoration:blur:size " + std::to_string(sz));
            }
        } else if (g_state.blurSaved) {
            if (!g_state.savedBlurSize.empty())
                HyprlandAPI::invokeHyprctlCommand("keyword", "decoration:blur:size " + g_state.savedBlurSize);
            if (!g_state.savedBlurPasses.empty())
                HyprlandAPI::invokeHyprctlCommand("keyword", "decoration:blur:passes " + g_state.savedBlurPasses);
            if (!g_state.savedBlurEnabled.empty())
                HyprlandAPI::invokeHyprctlCommand("keyword", "decoration:blur:enabled " + g_state.savedBlurEnabled);
            g_state.blurSaved    = false;
            g_state.lastBlurSize = -1;
        }
    }

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

    void startLaunchpadAnimTo(bool open) {
        g_state.lpTarget    = open ? 1.0F : 0.0F;
        g_state.lpAnimating = true;
        g_state.lastTick    = std::chrono::steady_clock::now();
        sendLaunchpadCmd(open ? "open" : "close");
        damageActiveMonitor();
    }

    void restoreIfShown() {
        if (g_state.desktopShown || g_state.gesturing || g_state.currentProgress > 0.001F) {
            g_state.gesturing = false;
            startAnimationTo(false);
        }
    }

    void hkRenderWindow(void* thisptr, Render::CRenderContext& ctx, PHLWINDOW pWindow, PHLMONITOR pMonitor, const Render::SWindowRenderPresentation& presentation,
                        const Time::steady_tp& now, bool allowDim, Render::eRenderPassMode mode, bool ignorePosition, bool standalone) {
        const auto origFn = reinterpret_cast<RenderWindowFn>(g_state.renderWindowHook->m_original);

        if ((g_state.currentProgress > 0.0005F || g_state.lpProgress > 0.0005F) && pWindow && pMonitor && pWindow->mapped() && !pWindow->isHidden()) {
            const auto targetMon = g_state.activeMonitor.lock();
            if (!targetMon || targetMon == pMonitor) {
                const bool onActiveWS    = (pWindow->m_workspace == pMonitor->m_activeWorkspace);
                const bool isPinnedOnMon = ((pWindow->m_state & Desktop::View::WINDOW_STATE_PINNED) != Desktop::View::WINDOW_STATE_NONE && pWindow->m_monitor == pMonitor);

                if (onActiveWS || isPinnedOnMon) {
                    Render::SWindowRenderPresentation modPres = presentation;

                    if (g_state.currentProgress > 0.0005F) {
                        const Vector2D winPos  = pWindow->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
                        const Vector2D winSize = pWindow->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT);
                        const size_t   idx     = windowIndexOnMonitor(pWindow, pMonitor);
                        const Vector2D offset  = computeScatterOffset(winPos, winSize, pMonitor->m_position, pMonitor->m_size, idx);
                        modPres.floatingOffset += offset * static_cast<double>(g_state.currentProgress);
                    }

                    // As Launchpad opens (0% -> 90%), fade out windows behind it so only
                    // the blurred wallpaper remains visible behind Launchpad at >= 90%.
                    if (g_state.lpProgress > 0.0005F) {
                        const float winAlpha = std::clamp(1.0F - (g_state.lpProgress / 0.90F), 0.0F, 1.0F);
                        if (winAlpha <= 0.001F)
                            return;
                        modPres.alpha *= winAlpha;
                        modPres.fadeAlpha *= winAlpha;
                    }

                    origFn(thisptr, ctx, pWindow, pMonitor, modPres, now, allowDim, mode, ignorePosition, standalone);
                    return;
                }
            }
        }

        origFn(thisptr, ctx, pWindow, pMonitor, presentation, now, allowDim, mode, ignorePosition, standalone);
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

    const auto matches          = HyprlandAPI::findFunctionsByName(PHANDLE, "renderWindow");
    void*      renderWindowAddr = nullptr;
    for (const auto& m : matches) {
        if (m.demangled.contains("IHyprRenderer::renderWindow")) {
            renderWindowAddr = m.address;
            break;
        }
    }
    if (!renderWindowAddr) {
        HyprlandAPI::addNotification(PHANDLE, "[hypr-showdesktop] IHyprRenderer::renderWindow bulunamadı!", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("IHyprRenderer::renderWindow not found");
    }

    g_state.renderWindowHook = HyprlandAPI::createFunctionHook(PHANDLE, renderWindowAddr, reinterpret_cast<void*>(&hkRenderWindow));
    if (!g_state.renderWindowHook || !g_state.renderWindowHook->hook()) {
        HyprlandAPI::addNotification(PHANDLE, "[hypr-showdesktop] renderWindow hook kurulamadı!", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("Failed to hook renderWindow");
    }

    initLaunchpadIPC();
    HyprlandAPI::addDispatcherV2(PHANDLE, "showdesktop", dispatchShowDesktop);

    g_state.pinchBeginListener = Event::bus()->m_events.gesture.pinch.begin.listen([](const IPointer::SPinchBeginEvent& e, Event::SCallbackInfo& info) {
        if (e.fingers < 3)
            return;

        const bool sdActive = g_state.desktopShown || g_state.currentProgress > 0.01F;
        const bool lpActive = isLaunchpadOpen() || g_state.lpProgress > 0.01F;
        const bool sdOn     = isShowDesktopEnabled();
        const bool lpOn     = isLaunchpadEnabled();

        if (!sdActive && !lpActive && !sdOn && !lpOn)
            return;

        info.cancelled        = true;
        g_state.gesturing     = true;
        g_state.animating     = false;
        g_state.lpAnimating   = false;
        g_state.activeMonitor = Desktop::focusState()->monitor();
        g_state.startScale    = 1.0F;
        g_state.lastSentLp    = -1.0F;

        if (sdActive) {
            g_state.gestureMode   = MODE_SHOW_DESKTOP;
            g_state.startShown    = g_state.desktopShown;
            g_state.startProgress = g_state.currentProgress;
        } else if (lpActive) {
            g_state.gestureMode   = MODE_LAUNCHPAD;
            g_state.startShown    = true;
            g_state.startProgress = (g_state.lpProgress > 0.01F) ? g_state.lpProgress : 1.0F;
            g_state.lpProgress    = g_state.startProgress;
        } else {
            g_state.gestureMode   = MODE_UNDECIDED;
            g_state.startShown    = false;
            g_state.startProgress = 0.0F;
            g_state.lpProgress    = 0.0F;
        }
    });

    g_state.pinchUpdateListener = Event::bus()->m_events.gesture.pinch.update.listen([](const IPointer::SPinchUpdateEvent& e, Event::SCallbackInfo& info) {
        if (!g_state.gesturing)
            return;

        info.cancelled       = true;
        const float rawScale = static_cast<float>(e.scale);

        if (g_state.gestureMode == MODE_UNDECIDED) {
            if (rawScale > 1.025F) {
                if (!isShowDesktopEnabled()) {
                    g_state.gesturing   = false;
                    g_state.gestureMode = MODE_NONE;
                    return;
                }
                g_state.gestureMode   = MODE_SHOW_DESKTOP;
                g_state.startProgress = 0.0F;
                g_state.startScale    = rawScale;
            } else if (rawScale < 0.975F) {
                if (!isLaunchpadEnabled()) {
                    g_state.gesturing   = false;
                    g_state.gestureMode = MODE_NONE;
                    return;
                }
                g_state.gestureMode   = MODE_LAUNCHPAD;
                g_state.startProgress = 0.0F;
                g_state.startScale    = rawScale;
            } else {
                return;
            }
        }

        const float relScale = std::max(0.1F, rawScale / g_state.startScale);

        if (g_state.gestureMode == MODE_SHOW_DESKTOP) {
            const float deltaP = std::log2(relScale) * 1.45F;
            const float rawP   = g_state.startProgress + deltaP;

            if (rawP > 1.0F) {
                g_state.currentProgress = 1.0F;
                g_state.startProgress   = 1.0F;
                g_state.startScale      = std::max(0.01F, rawScale);
            } else if (rawP < 0.0F) {
                g_state.currentProgress = 0.0F;
                g_state.startProgress   = 0.0F;
                g_state.startScale      = std::max(0.01F, rawScale);
            } else {
                g_state.currentProgress = rawP;
            }
            damageActiveMonitor();
        } else if (g_state.gestureMode == MODE_LAUNCHPAD) {
            const float deltaP = -std::log2(relScale) * 1.55F;
            const float rawP   = g_state.startProgress + deltaP;

            if (rawP > 1.0F) {
                g_state.lpProgress    = 1.0F;
                g_state.startProgress = 1.0F;
                g_state.startScale    = std::max(0.01F, rawScale);
            } else if (rawP < 0.0F) {
                g_state.lpProgress    = 0.0F;
                g_state.startProgress = 0.0F;
                g_state.startScale    = std::max(0.01F, rawScale);
            } else {
                g_state.lpProgress = rawP;
            }

            sendLaunchpadProgressThrottled(g_state.lpProgress);
            updateLaunchpadBlur(g_state.lpProgress);
            damageActiveMonitor();
        }
    });

    g_state.pinchEndListener = Event::bus()->m_events.gesture.pinch.end.listen([](const IPointer::SPinchEndEvent& e, Event::SCallbackInfo& info) {
        if (!g_state.gesturing)
            return;

        info.cancelled      = true;
        g_state.gesturing   = false;
        const auto mode     = g_state.gestureMode;
        g_state.gestureMode = MODE_NONE;

        if (mode == MODE_SHOW_DESKTOP) {
            if (e.cancelled) {
                startAnimationTo(g_state.startShown);
                return;
            }
            if (!g_state.startShown)
                startAnimationTo(g_state.currentProgress > 0.25F);
            else
                startAnimationTo(g_state.currentProgress > 0.75F);
        } else if (mode == MODE_LAUNCHPAD) {
            if (e.cancelled) {
                startLaunchpadAnimTo(g_state.startShown);
                return;
            }
            if (!g_state.startShown)
                startLaunchpadAnimTo(g_state.lpProgress > 0.25F);
            else
                startLaunchpadAnimTo(g_state.lpProgress > 0.75F);
        }
    });

    g_state.renderPreListener = Event::bus()->m_events.render.pre.listen([](PHLMONITOR pMonitor) {
        const auto targetMon = g_state.activeMonitor.lock();
        if (targetMon && pMonitor != targetMon)
            return;

        // If Launchpad was closed externally (Esc / click / app launch), fade windows back in
        if (!g_state.gesturing && !g_state.lpAnimating && g_state.lpProgress > 0.01F && !isLaunchpadOpen()) {
            g_state.lpTarget    = 0.0F;
            g_state.lpAnimating = true;
            g_state.lastTick    = std::chrono::steady_clock::now();
        }

        if (!g_state.animating && !g_state.lpAnimating)
            return;

        const auto  now = std::chrono::steady_clock::now();
        const float dt  = std::clamp(std::chrono::duration<float>(now - g_state.lastTick).count(), 0.0005F, 0.05F);
        g_state.lastTick = now;

        constexpr float SPEED = 16.0F;
        const float     alpha = 1.0F - std::exp(-SPEED * dt);

        if (g_state.animating) {
            g_state.currentProgress += (g_state.targetProgress - g_state.currentProgress) * alpha;
            if (std::abs(g_state.targetProgress - g_state.currentProgress) < 0.0015F) {
                g_state.currentProgress = g_state.targetProgress;
                g_state.animating       = false;
            }
        }

        if (g_state.lpAnimating) {
            g_state.lpProgress += (g_state.lpTarget - g_state.lpProgress) * alpha;
            if (std::abs(g_state.lpTarget - g_state.lpProgress) < 0.0015F) {
                g_state.lpProgress  = g_state.lpTarget;
                g_state.lpAnimating = false;
            }
            updateLaunchpadBlur(g_state.lpProgress);
        }
    });

    g_state.renderStageListener = Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& e) {
        if ((!g_state.animating && !g_state.lpAnimating) || e.stage != RENDER_POST || !e.monitor)
            return;

        const auto targetMon = g_state.activeMonitor.lock();
        if (!targetMon || e.monitor == targetMon)
            g_pHyprRenderer->damageMonitor(e.monitor);
    });

    g_state.windowOpenListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW) {
        restoreIfShown();
    });

    g_state.workspaceChangeListener = Event::bus()->m_events.workspace.active.listen([](PHLWORKSPACE) {
        restoreIfShown();
    });

    return {"hypr-showdesktop", "macOS-style 1:1 Show Desktop + Launchpad", "jarn", "2.1.3"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_state.animating       = false;
    g_state.lpAnimating     = false;
    g_state.gesturing       = false;
    g_state.desktopShown    = false;
    g_state.currentProgress = 0.0F;
    g_state.lpProgress      = 0.0F;
    updateLaunchpadBlur(0.0F);
    damageActiveMonitor();

    if (g_state.lpSockFd >= 0) {
        close(g_state.lpSockFd);
        g_state.lpSockFd = -1;
    }

    g_state.pinchBeginListener.reset();
    g_state.pinchUpdateListener.reset();
    g_state.pinchEndListener.reset();
    g_state.renderPreListener.reset();
    g_state.renderStageListener.reset();
    g_state.windowOpenListener.reset();
    g_state.workspaceChangeListener.reset();

    if (g_state.renderWindowHook) {
        HyprlandAPI::removeFunctionHook(PHANDLE, g_state.renderWindowHook);
        g_state.renderWindowHook = nullptr;
    }
}
