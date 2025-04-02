SKIPUNZIP=0
. "$MODPATH"/util_functions.sh
api_level_arch_detect
magisk_path=/data/adb/modules/
module_id=$(grep_prop id $MODPATH/module.prop)

if [[ "$KSU" == "true" ]]; then
  ui_print "- KernelSU 用户空间版本号: $KSU_VER_CODE"
  ui_print "- KernelSU 内核空间版本号: $KSU_KERNEL_VER_CODE"
  if [ "$KSU_KERNEL_VER_CODE" -lt 11089 ]; then
    ui_print "*********************************************"
    ui_print "! 请安装 KernelSU 管理器 v0.6.2 或更高版本"
    abort "*********************************************"
  fi
elif [[ "$APATCH" == "true" ]]; then
  ui_print "- APatch 版本名: $APATCH_VER"
  ui_print "- APatch 版本号: $APATCH_VER_CODE"
else
  ui_print "- Magisk 版本名: $MAGISK_VER"
  ui_print "- Magisk 版本号: $MAGISK_VER_CODE"
  if [ "$MAGISK_VER_CODE" -lt 26000 ]; then
    ui_print "*********************************************"
    ui_print "! 请安装 Magisk 26.0+"
    abort "*********************************************"
  fi
fi

# 赋予文件夹权限
set_perm_recursive "$MODPATH" 0 0 0755 0777 u:object_r:system_file:s0

# 重置缓存
rm -rf /data/system/package_cache/*

# 环境配置
touch "$MODPATH"/system.prop
device_code="$(getprop ro.product.device)"
device_soc_name="$(getprop ro.vendor.qti.soc_name)"
device_soc_model="$(getprop ro.vendor.qti.soc_model)"

has_been_patch_device_features=0
has_been_patch_perfinit_bdsize_zram=0


# ZRAM:RAM 1:1内存优化
need_patch_zram_phone_list="rubens marble duchamp manet rothko vermeer matisse xaga ingres diting alioth ares corot haydn mondrian rembrandt socrates"
is_need_patch_zram=$(check_device_is_need_patch "$device_code" "$need_patch_zram_phone_list")

# 基础函数
add_props() {
  local line="$1"
  echo "$line" >>"$MODPATH"/system.prop
}

add_post_fs_data() {
  local line="$1"
  printf "\n$line\n" >>"$MODPATH"/post-fs-data.sh
}

add_service() {
  local line="$1"
  printf "\n$line\n" >>"$MODPATH"/service.sh
}

key_check() {
  while true; do
    key_check=$(/system/bin/getevent -qlc 1)
    key_event=$(echo "$key_check" | awk '{ print $3 }' | grep 'KEY_')
    key_status=$(echo "$key_check" | awk '{ print $4 }')
    if [[ "$key_event" == *"KEY_"* && "$key_status" == "DOWN" ]]; then
      keycheck="$key_event"
      break
    fi
  done
  while true; do
    key_check=$(/system/bin/getevent -qlc 1)
    key_event=$(echo "$key_check" | awk '{ print $3 }' | grep 'KEY_')
    key_status=$(echo "$key_check" | awk '{ print $4 }')
    if [[ "$key_event" == *"KEY_"* && "$key_status" == "UP" ]]; then
      break
    fi
  done
}

if [[ -d "$magisk_path$module_id" ]]; then
  ui_print "*********************************************"
  ui_print "模块不支持覆盖更新，请卸载模块并重启手机后再尝试安装！"
  abort "*********************************************"
fi
# 骁龙8+Gen1机型判断
if [[ "$device_soc_model" == "SM8475" && "$device_soc_name" == "cape" && "$API" -ge 33 ]]; then
  # 调整I/O调度
  ui_print "*********************************************"
  ui_print "- 检测到你的设备处理器属于骁龙8+Gen1"
  ui_print "- 目前骁龙8+Gen1机型存在系统IO调度异常的问题，容易导致系统卡顿或者无响应，模块可以为你开启合适的I/O调度规则"
  ui_print "- 是否调整系统I/O调度？"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "*********************************************"
    ui_print "- 请选择需要使用的系统I/O调度？"
    ui_print "  音量+ ：启用智能I/O调度"
    ui_print "  音量- ：启用系统默认I/O调度"
    ui_print "*********************************************"
    key_check
    if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
      ui_print "*********************************************"
      ui_print "- 已开启智能I/O调度(Android 14+ 生效)"
      add_props "# 开启智能I/O调度"
      add_props "persist.sys.stability.smartfocusio=on"
      ui_print "*********************************************"
    else
      ui_print "*********************************************"
      ui_print "- 已启用系统默认I/O调度(Android 14+ 生效)"
      add_props "# 开启系统默认I/O调度"
      add_props "persist.sys.stability.smartfocusio=off"
      ui_print "*********************************************"
    fi
  else
    ui_print "- 你选择不调整系统I/O调度"
  fi
fi

# ZRAM:RAM=1:1 内存优化
if [[ "$is_need_patch_zram" == 1 && "$API" -ge 35 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否启用 ZRAM:RAM=1:1 内存优化?（第三方内核可能不生效）"
  ui_print "- [重要提醒]内存优化最大兼容 ZRAM 为 16G"
  ui_print "- [重要提醒]可能会与其他内存相关模块冲突导致不生效"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已启用 ZRAM:RAM=1:1 内存优化"
    ui_print "- [重要提醒]内存优化最大兼容 ZRAM 为 16G"
    ui_print "- [重要提醒]可能会与其他内存相关模块冲突导致不生效"
    if [[ "$has_been_patch_perfinit_bdsize_zram" == 0 ]]; then
      has_been_patch_perfinit_bdsize_zram=1
      patch_perfinit_bdsize_zram $MODPATH
      add_service 'patch_perfinit_bdsize_zram $MODDIR'
    fi
    patch_zram_config $MODPATH
    add_service 'patch_zram_config $MODDIR'
  else
    ui_print "- 你选择不启用 ZRAM:RAM=1:1 内存优化"
  fi
fi

if [[ "$API" -ge 35 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否启用dm设备映射器？（第三方内核可能不生效）"
  ui_print "- [重要提醒]一般推荐启用，通常用于将设备上的冷数据压缩并迁移到硬盘上"
  ui_print "- [重要提醒]需要开启内存扩展才会生效"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已开启dm设备映射器"
    ui_print "- [重要提醒]需要开启内存扩展才会生效"
    add_props "# 开启dm设备映射器"
    add_props "persist.miui.extm.dm_opt.enable=true"
  else
    ui_print "- 你选择不开启dm设备映射器"
  fi
fi

if [[ "$API" -le 35 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否关闭应用预加载？"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已关闭应用预加载"
    add_props "# 关闭应用预加载"
    add_props "persist.sys.prestart.proc=false"
  else
    ui_print "- 你选择不关闭应用预加载"
  fi
fi

if [[ "$API" -ge 33 && -f "/system/product/etc/permissions/cn.google.services.xml" ]]; then
  # 解除GMS区域限制
  ui_print "*********************************************"
  ui_print "- 是否解除谷歌服务框架的区域限制？"
  ui_print "- [重要提醒]解除谷歌服务框架区域限制后可以使用 Google Play 快速分享等功能~"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已解除谷歌服务框架的区域限制"
    patch_cn_google_services $MODPATH
    add_post_fs_data 'patch_cn_google_services $MODDIR'
  else
    ui_print "- 你选择不解除谷歌服务框架的区域限制"
  fi
fi

# 解锁视频工具箱智能刷新率
ui_print "*********************************************"
ui_print "- 是否解锁视频工具箱智能刷新率(移植包可能不兼容)"
ui_print "  音量+ ：是"
ui_print "  音量- ：否"
ui_print "*********************************************"
key_check
if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
  ui_print "- 已解锁视频工具箱智能刷新率"
  if [[ "$has_been_patch_device_features" == 0 ]]; then
    has_been_patch_device_features=1
    patch_device_features $MODPATH
    add_post_fs_data 'patch_device_features $MODDIR'
  fi
  patch_support_video_dfps $MODPATH
  add_post_fs_data 'patch_support_video_dfps $MODDIR'
else
  ui_print "- 你选择不解锁视频工具箱智能刷新率"
fi

# 静置保持当前应用刷新率上限
if [[ "$API" -le 34 ]]; then
  ui_print "*********************************************"
  ui_print "- 静置时是否保持当前应用刷新率上限？"
  ui_print "- [重要提示]此功能会增加系统功耗，耗电量和发热都会比日常系统策略激进，请谨慎开启！！！"
  ui_print "- [重要提示]静置保持144hz刷新率会导致小米触控笔无法正常工作，使用触控笔请务必调整到120hz！！！"
  ui_print "- [重要提示]此功能非必要情况下不推荐开启~"
  ui_print "  音量+ ：是，且了解该功能会影响小米触控笔"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 你选择静置时保持当前应用刷新率上限"
    ui_print "- [你已知晓]静置保持144hz刷新率会导致小米触控笔无法正常工作，使用触控笔请务必调整到120hz！！！"
    add_props "# 静置保持当前应用刷新率上限"
    add_props "ro.surface_flinger.use_content_detection_for_refresh_rate=true"
    add_props "ro.surface_flinger.set_idle_timer_ms=2147483647"
    add_props "ro.surface_flinger.set_touch_timer_ms=2147483647"
    add_props "ro.surface_flinger.set_display_power_timer_ms=2147483647"
  else
    ui_print "- 你选择静置时使用系统默认配置，不需要保持当前应用刷新率上限"
  fi
fi

# 解锁节律护眼
if [[ "$API" -ge 34 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否解锁节律护眼(Hyper OS 生效，移植包可能不兼容)"
  ui_print "- [重要提醒]是否生效以实际系统底层支持情况为准"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    if [[ "$has_been_patch_device_features" == 0 ]]; then
      has_been_patch_device_features=1
      patch_device_features $MODPATH
      add_post_fs_data 'patch_device_features $MODDIR'
    fi
    patch_eyecare_mode $MODPATH
    add_post_fs_data 'patch_eyecare_mode $MODDIR'
    ui_print "- 已解锁节律护眼(Hyper OS 生效)"
  else
    ui_print "- 你选择不解锁节律护眼"
  fi
fi

# 开启极致模式
ui_print "*********************************************"
ui_print "- 是否开启极致模式"
ui_print "  音量+ ：是"
ui_print "  音量- ：否"
ui_print "*********************************************"
key_check
if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
  ui_print "- 已开启极致模式"
  ui_print "- 极致模式的设置路径位于[开发者选项-极致模式]"
  settings put secure speed_mode_enable 1
else
  ui_print "- 你选择不开启极致模式"
  settings put secure speed_mode_enable 0
fi

# 解锁游戏工具箱狂暴引擎UI界面
if [[ "$API" -ge 33 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否解锁游戏工具箱\"狂暴引擎\"UI界面？(移植包可能不兼容)"
  ui_print "- [重要提示]该功能仅为开启\"狂暴引擎\"的UI界面，并非真的添加\"狂暴引擎\"功能，也无法开启feas！！！"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已解锁游戏工具箱\"狂暴引擎\"UI界面"
    ui_print "- [你已知晓]该功能仅为开启\"狂暴引擎\"的UI界面，并非真的添加\"狂暴引擎\"功能，也无法开启feas！！！"
    if [[ "$has_been_patch_device_features" == 0 ]]; then
      has_been_patch_device_features=1
      patch_device_features $MODPATH
      add_post_fs_data 'patch_device_features $MODDIR'
    fi
    patch_wild_boost $MODPATH
    add_post_fs_data 'patch_wild_boost $MODDIR'
  else
    ui_print "- 你选择不解锁游戏工具箱\"狂暴引擎\"UI界面"
  fi
fi

# 开启进游戏三倍速
if [[ "$API" -ge 33 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否开启进游戏三倍速"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已开启进游戏三倍速"
    add_props "# 开启进游戏三倍速"
    add_props "debug.game.video.support=true"
    add_props "debug.game.video.speed=true"
  else
    ui_print "- 你选择不开启进游戏三倍速"
  fi
fi

# 移除OTA验证
ui_print "*********************************************"
ui_print "- 是否移除OTA验证？"
ui_print "- [你已知晓]可绕过 ROM 权限校验"
ui_print "- [你已知晓]不支持任何非官方 ROM 使用"
ui_print "- [你已知晓]此功能有一定危险性，请在了解 Fastboot 操作后再评估是否开启"
ui_print "  音量+ ：是"
ui_print "  音量- ：否"
ui_print "*********************************************"
key_check
if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
  ui_print "- 已移除OTA验证"
  if [[ "$has_been_patch_device_features" == 0 ]]; then
    has_been_patch_device_features=1
    patch_device_features $MODPATH
    add_post_fs_data 'patch_device_features $MODDIR'
  fi
  patch_disabled_ota_validate $MODPATH
  add_post_fs_data 'patch_disabled_ota_validate $MODDIR'
else
  ui_print "- 你选择不移除OTA验证"
fi

# 解锁游戏音质优化开关
ui_print "*********************************************"
ui_print "- 是否解锁\"游戏音质优化\"开关"
ui_print "  音量+ ：是"
ui_print "  音量- ：否"
ui_print "*********************************************"
key_check
if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
  ui_print "- 已解锁\"游戏音质优化\"开关"
  ui_print "- \"游戏音质优化\"开关设置路径位于[游戏工具箱-性能增强]"
  add_props "# 解锁\"游戏音质优化\"开关"
  add_props "ro.vendor.audio.game.effect=true"
else
  ui_print "- 你选择不解锁\"游戏音质优化\"开关"
fi

# 开启平滑圆角
ui_print "*********************************************"
ui_print "- 是否开启平滑圆角"
ui_print "  音量+ ：是"
ui_print "  音量- ：否"
ui_print "*********************************************"
key_check
if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
  ui_print "- 已开启平滑圆角"
  add_props "# 开启平滑圆角"
  add_props "persist.sys.support_view_smoothcorner=true"
  add_props "persist.sys.support_window_smoothcorner=true"
else
  ui_print "- 你选择不开启平滑圆角"
fi

# 支持全屏AOD
if [[ "$API" -ge 35 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否开启全屏AOD显示？"
  ui_print "- [你已知晓]功能实际是否支持受系统和硬件影响"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已开启全屏AOD显示"
    add_props "# 开启开启全屏AOD显示"
    if [[ "$has_been_patch_device_features" == 0 ]]; then
      has_been_patch_device_features=1
      patch_device_features $MODPATH
      add_post_fs_data 'patch_device_features $MODDIR'
    fi
    patch_support_aod_fullscreen $MODPATH
    add_post_fs_data 'patch_support_aod_fullscreen $MODDIR'
  else
    ui_print "*********************************************"
    ui_print "- 你选择不开启全屏AOD显示"
    ui_print "*********************************************"
  fi
fi

# 支持高级材质
if [[ "$API" -ge 34 && "$is_un_need_patch_background_blur" == '0' ]]; then
  ui_print "*********************************************"
  ui_print "- 是否开启高级材质"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已开启高级材质"
    add_props "# 开启高级材质"
    add_props "persist.sys.background_blur_supported=true"
    add_props "persist.sys.background_blur_status_default=true"
    add_props "persist.sys.background_blur_version=2"
    add_props "persist.sys.advanced_visual_release=3"
  else
    ui_print "*********************************************"
    ui_print "- 你选择不开启高级材质"
    ui_print "*********************************************"
  fi
fi

if [[  "$API" -ge 34 ]]; then
  ui_print "*********************************************"
  ui_print "- 是否启用通信共享？(仅在默认主题下生效)"
  ui_print "- [重要提醒]是否生效以实际系统底层支持情况为准"
  ui_print "- [重要提醒]如果无效请授予[系统界面]和[系统桌面]的ROOT权限"
  ui_print "  音量+ ：是"
  ui_print "  音量- ：否"
  ui_print "*********************************************"
  key_check
  if [[ "$keycheck" == "KEY_VOLUMEUP" ]]; then
    ui_print "- 已启用通信共享，仅在默认主题下生效"
    ui_print "- [重要提醒]是否生效以实际系统底层支持情况为准"
    ui_print "- [重要提醒]如果无效请授予[系统界面]和[系统桌面]的ROOT权限"
    patch_celluar_shared $MODPATH
  else
    ui_print "- 你选择不启用通信共享"
  fi
fi

ui_print "*********************************************"
ui_print "- 好诶w，模块已经安装完成了，重启手机后生效"
ui_print "- 功能具体支持情况以系统为准"
ui_print "*********************************************"
