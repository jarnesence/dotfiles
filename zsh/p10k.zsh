# Powerlevel10k config — leanest possible, no icons, transient prompt
# Source: ~/Claude/dotfiles/zsh/p10k.zsh (symlink → ~/.p10k.zsh)

# Sadece path + prompt char. VCS icon sorunu için çıkarıldı.
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir prompt_char)
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=()

# Flat / lean görünüm
typeset -g POWERLEVEL9K_BACKGROUND=
typeset -g POWERLEVEL9K_MODE=compatible                  # nerdfont icon auto-detect KAPALI
typeset -g POWERLEVEL9K_ICON_PADDING=none

# Segment separator'ları sil — kullanıcı her yerde icon istemiyor
typeset -g POWERLEVEL9K_LEFT_SEGMENT_SEPARATOR=''
typeset -g POWERLEVEL9K_RIGHT_SEGMENT_SEPARATOR=''
typeset -g POWERLEVEL9K_LEFT_SUBSEGMENT_SEPARATOR=' '
typeset -g POWERLEVEL9K_RIGHT_SUBSEGMENT_SEPARATOR=' '
typeset -g POWERLEVEL9K_{LEFT,RIGHT}_{LEFT,RIGHT}_WHITESPACE=''

# Prompt char = ⟩ (başarı yeşil, hata kırmızı)
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_{VIINS,VICMD,VIVIS,VIOWR}_CONTENT_EXPANSION='⟩'
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_{VIINS,VICMD,VIVIS,VIOWR}_CONTENT_EXPANSION='⟩'
# Fastfetch WM label'ıyla aynı renk: ANSI 32 → kitty palette'inden color2 çekilir
# (matugen'in palette.sh'tan ürettiği tertiary tonu). Hata sabit kırmızı.
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VIINS_FOREGROUND=2
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VIINS_FOREGROUND=1
typeset -g POWERLEVEL9K_PROMPT_CHAR_OK_VICMD_FOREGROUND=2
typeset -g POWERLEVEL9K_PROMPT_CHAR_ERROR_VICMD_FOREGROUND=1

# Dir: tam yol gösterilir. Son klasör (anchor) parlak, öncekiler silik.
# Separator: ` / ` (her yanında 1 boşluk).
typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=none
typeset -g POWERLEVEL9K_DIR_FOREGROUND=8                # silik gri (önceki klasörler)
typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=2         # son klasör: fastfetch WM rengi
typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=true
typeset -g POWERLEVEL9K_DIR_PATH_SEPARATOR=' / '
typeset -g POWERLEVEL9K_DIR_PATH_SEPARATOR_FOREGROUND=8  # separator'lar da silik
typeset -g POWERLEVEL9K_DIR_CLASSES=(
    '~'                HOME            ''
    '~/*'              HOME_SUBFOLDER  ''
    '/etc|/etc/*'      ETC             ''
    '*'                DEFAULT         ''
)
typeset -g POWERLEVEL9K_DIR_{HOME,HOME_SUBFOLDER,HOME_NON_WRITABLE,DEFAULT,NON_EXISTENT,NOT_WRITABLE,ETC}_VISUAL_IDENTIFIER_EXPANSION=''
typeset -g POWERLEVEL9K_DIR_VISUAL_IDENTIFIER_EXPANSION=''

# Transient prompt — Enter sonrası geçmişteki prompt sadece ⟩ olarak collapse olur
typeset -g POWERLEVEL9K_TRANSIENT_PROMPT=always

# Instant prompt KAPALI — fastfetch kitty graphics ile çakışıyor
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

# Her prompt'tan önce 1 boş satır
typeset -g POWERLEVEL9K_PROMPT_ADD_NEWLINE=true
