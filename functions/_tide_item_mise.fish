set -U tide_mise_icon '󰆍'
set -U tide_mise_color 00D9FF
set -U tide_mise_bg_color 161618
set -U tide_mise_icon_color $tide_mise_color
set -U tide_mise_config_color $tide_mise_color

function __mise_prompt
    set -f current_cfg (eval "path resolve $(mise cfg ls --no-header | tail -n 1 | string split -f1 ' ')")
    set -f path_segments (string replace --regex "^$HOME" "~" -- "$current_cfg" | string split /)

    set_color $tide_mise_config_color
    for segment in $path_segments[1..-2]
        printf "%s/" (string sub --length 1 $segment)
    end

    printf "%s/" $path_segments[-2]
    printf "%s " $path_segments[-1]
end

function _tide_item_mise
    if set -q __MISE_DIFF && test -n "$__MISE_DIFF"
        _tide_print_item mise (set_color $tide_mise_icon_color)$tide_mise_icon' '(__mise_prompt)(set_color normal)
    end
end
