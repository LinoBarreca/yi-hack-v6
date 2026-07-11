#!/bin/sh

# 6.0.1 - yi-hack-v6
#
# restore_locked_configs.sh - stamp the build-time locked settings (config/locked.conf)
# back into their target config files. Runs at boot (apply_config.sh tail + system.sh
# after check_conf) and on demand. See locked_conf.sh.

. /home/yi-hack/base/script/locked_conf.sh

restore_locked_configs
