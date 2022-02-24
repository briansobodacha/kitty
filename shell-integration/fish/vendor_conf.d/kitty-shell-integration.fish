#!/bin/fish

# To use fish's autoloading feature, kitty prepends the vendored integration script directory to XDG_DATA_DIRS.
# The original paths needs to be restored here to not affect other programs.
# In particular, if the original XDG_DATA_DIRS does not exist, it needs to be removed.
if set -q KITTY_FISH_XDG_DATA_DIR
    if set -q XDG_DATA_DIRS
        set --global --export --path XDG_DATA_DIRS "$XDG_DATA_DIRS"
        if set -l index (contains -i "$KITTY_FISH_XDG_DATA_DIR" $XDG_DATA_DIRS)
            set --erase --global XDG_DATA_DIRS[$index]
            test -n "$XDG_DATA_DIRS" || set --erase --global XDG_DATA_DIRS
        end
        if set -q XDG_DATA_DIRS
            set --global --export --unpath XDG_DATA_DIRS "$XDG_DATA_DIRS"
        end
    end
    set --erase KITTY_FISH_XDG_DATA_DIR
end

status is-interactive || exit 0
not functions -q __ksi_schedule || exit 0
# Check fish version 3.3.0+ efficiently and exit on outdated versions
set -q fish_killring || exit 0

function __ksi_schedule --on-event fish_prompt -d "Setup kitty integration after other scripts have run, we hope"
    functions --erase __ksi_schedule
    test -n "$KITTY_SHELL_INTEGRATION" || return 0
    set --local _ksi (string split " " -- "$KITTY_SHELL_INTEGRATION")
    set --erase KITTY_SHELL_INTEGRATION

    # Enable cursor shape changes for default mode and vi mode
    if not contains "no-cursor" $_ksi
        and not functions -q __ksi_set_cursor

        function __ksi_block_cursor --on-event fish_preexec -d "Set cursor shape to blinking default shape before executing command"
            echo -en "\e[0 q"
        end

        function __ksi_set_cursor --on-variable fish_key_bindings -d "Set the cursor shape for different modes when switching key bindings"
            if test "$fish_key_bindings" = fish_default_key_bindings
                not functions -q __ksi_bar_cursor || return
                function __ksi_bar_cursor --on-event fish_prompt -d "Set cursor shape to blinking bar on prompt"
                    echo -en "\e[5 q"
                end
            else
                functions --erase __ksi_bar_cursor
                contains "$fish_key_bindings" fish_vi_key_bindings fish_hybrid_key_bindings
                and __ksi_set_vi_cursor
            end
        end

        function __ksi_set_vi_cursor -d "Set the vi mode cursor shapes"
            # Set the vi mode cursor shapes only when none of them are configured
            set --local vi_modes fish_cursor_{default,insert,replace_one,visual}
            set -q $vi_modes
            test "$status" -eq 4 || return

            set --local vi_cursor_shapes block line underscore block
            for i in 1 2 3 4
                set --global $vi_modes[$i] $vi_cursor_shapes[$i] blink
            end

            # Change the cursor shape for current mode
            test "$fish_bind_mode" = "insert" && echo -en "\e[5 q" || echo -en "\e[1 q"
        end

        __ksi_set_cursor
        functions -q __ksi_bar_cursor
        and __ksi_bar_cursor
    end

    # Enable prompt marking with OSC 133
    if not contains "no-prompt-mark" $_ksi
        and not set -q __ksi_prompt_state
        set --global __ksi_prompt_state first-run

        function __ksi_prompt_start
            # Preserve the command exit code from $status
            set --local cmd_status $status
            if contains "$__ksi_prompt_state" post-exec first-run
                echo -en "\e]133;D\a"
            end
            set --global __ksi_prompt_state prompt-start
            echo -en "\e]133;A\a"
            return $cmd_status
        end

        function __ksi_prompt_end
            set --local cmd_status $status
            # fish trims one trailing newline from the output of fish_prompt, so
            # we need to do the same. See https://github.com/kovidgoyal/kitty/issues/4032
            set --local op (__ksi_original_fish_prompt) # op is a list because fish splits on newlines in command substitution
            if set -q op[2]
                printf '%s\n' $op[1..-2] # print all but last element of the list, each followed by a new line
            end
            printf '%s' $op[-1] # print the last component without a newline
            set --global __ksi_prompt_state prompt-end
            echo -en "\e]133;B\a"
            return $cmd_status
        end

        functions -c fish_prompt __ksi_original_fish_prompt

        # Check whether the mode prompt function exists and is not empty
        if functions --no-details fish_mode_prompt | string match -qnvr '^ *(#|function |end$|$)'
            # When vi mode changes, fish redraws fish_prompt when fish_mode_prompt is empty.
            # Some prompt rely on this side effect to draw vi mode indicator.
            # See https://github.com/starship/starship/issues/1283
            functions -c fish_mode_prompt __ksi_original_fish_mode_prompt
            function fish_mode_prompt
                __ksi_prompt_start
                __ksi_original_fish_mode_prompt
            end
            function fish_prompt
                __ksi_prompt_end
            end
        else
            function fish_prompt
                __ksi_prompt_start
                __ksi_prompt_end
            end
        end

        function __ksi_mark_output_start --on-event fish_preexec
            set --global __ksi_prompt_state pre-exec
            echo -en "\e]133;C\a"
        end

        function __ksi_mark_output_end --on-event fish_postexec
            set --global __ksi_prompt_state post-exec
            echo -en "\e]133;D;$status\a"
        end

        # With prompt marking, kitty clears the current prompt on resize,
        # so we need fish to redraw it.
        set --global fish_handle_reflow 1
    end
end
