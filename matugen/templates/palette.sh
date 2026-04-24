# Source of truth palette — matugen wallpaper'dan üretir.
# Canlı path: ~/.config/palette/palette.sh
# Template:   ~/Claude/dotfiles/matugen/templates/palette.sh
#
# Tüm uygulamalar bu dosyadan okur (generate-themes.sh aracılığıyla).
# EL İLE DÜZENLEME — wallpaper değişince üzerine yazılır.

export P_PRIMARY='{{colors.primary.default.hex}}'
export P_ON_PRIMARY='{{colors.on_primary.default.hex}}'
export P_PRIMARY_CONTAINER='{{colors.primary_container.default.hex}}'
export P_ON_PRIMARY_CONTAINER='{{colors.on_primary_container.default.hex}}'

export P_SECONDARY='{{colors.secondary.default.hex}}'
export P_ON_SECONDARY='{{colors.on_secondary.default.hex}}'
export P_SECONDARY_CONTAINER='{{colors.secondary_container.default.hex}}'
export P_ON_SECONDARY_CONTAINER='{{colors.on_secondary_container.default.hex}}'

export P_TERTIARY='{{colors.tertiary.default.hex}}'
export P_ON_TERTIARY='{{colors.on_tertiary.default.hex}}'
export P_TERTIARY_CONTAINER='{{colors.tertiary_container.default.hex}}'
export P_ON_TERTIARY_CONTAINER='{{colors.on_tertiary_container.default.hex}}'

export P_SURFACE='{{colors.surface.default.hex}}'
export P_ON_SURFACE='{{colors.on_surface.default.hex}}'
export P_SURFACE_VARIANT='{{colors.surface_variant.default.hex}}'
export P_ON_SURFACE_VARIANT='{{colors.on_surface_variant.default.hex}}'

export P_BACKGROUND='{{colors.background.default.hex}}'
export P_ON_BACKGROUND='{{colors.on_background.default.hex}}'

export P_OUTLINE='{{colors.outline.default.hex}}'
export P_OUTLINE_VARIANT='{{colors.outline_variant.default.hex}}'

export P_ERROR='{{colors.error.default.hex}}'
export P_ON_ERROR='{{colors.on_error.default.hex}}'
export P_ERROR_CONTAINER='{{colors.error_container.default.hex}}'
export P_ON_ERROR_CONTAINER='{{colors.on_error_container.default.hex}}'

export P_SHADOW='{{colors.shadow.default.hex}}'
export P_INVERSE_SURFACE='{{colors.inverse_surface.default.hex}}'
export P_INVERSE_ON_SURFACE='{{colors.inverse_on_surface.default.hex}}'
export P_INVERSE_PRIMARY='{{colors.inverse_primary.default.hex}}'
