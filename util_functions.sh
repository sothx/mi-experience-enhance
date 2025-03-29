api_level_arch_detect() {
  API=$(getprop ro.build.version.sdk)
  ABI=$(getprop ro.product.cpu.abi)
  if [ "$ABI" = "x86" ]; then
    ARCH=x86
    ABI32=x86
    IS64BIT=false
  elif [ "$ABI" = "arm64-v8a" ]; then
    ARCH=arm64
    ABI32=armeabi-v7a
    IS64BIT=true
  elif [ "$ABI" = "x86_64" ]; then
    ARCH=x64
    ABI32=x86
    IS64BIT=true
  else
    ARCH=arm
    ABI=armeabi-v7a
    ABI32=armeabi-v7a
    IS64BIT=false
  fi
}

set_perm() {
  chown $2:$3 $1 || return 1
  chmod $4 $1 || return 1
  local CON=$5
  [ -z $CON ] && CON=u:object_r:system_file:s0
  chcon $CON $1 || return 1
}

set_perm_recursive() {
  find $1 -type d 2>/dev/null | while read dir; do
    set_perm $dir $2 $3 $4 $6
  done
  find $1 -type f -o -type l 2>/dev/null | while read file; do
    set_perm $file $2 $3 $5 $6
  done
}

grep_prop() {
  local REGEX="s/^$1=//p"
  shift
  local FILES=$@
  [ -z "$FILES" ] && FILES='/system/build.prop'
  cat $FILES 2>/dev/null | dos2unix | sed -n "$REGEX" | head -n 1
}

update_system_prop() {
  local prop="$1"
  local value="$2"
  local file="$3"

  if grep -q "^$prop=" "$file"; then
    # 如果找到匹配行，使用 sed 进行替换
    sed -i "s/^$prop=.*/$prop=$value/" "$file"
  else
    # 如果没有找到匹配行，追加新行
    printf "$prop=$value\n" >> "$file"
  fi
}

remove_system_prop() {
  local prop="$1"
  local file="$2"
  sed -i "/^$prop=/d" "$file"
}

# 获取设备类型
check_device_type() {
    local redmi_pad_list=$1
    local device_code=$2
    local result="xiaomi"
    for i in $redmi_pad_list; do
        if [[ "$device_code" == "$i" ]]; then
            result=redmi
            break
        fi
    done
    echo $result
}

# 根据机型列表判断是否需要补全对应机型的功能
check_device_is_need_patch() {
    local device_code=$1
    local pad_list=$2
    local result=0

    for i in $pad_list; do
        if [[ "$device_code" == "$i" ]]; then
            result=1
            break
        fi
    done

    echo $result
}

patch_device_features() {
  DEVICE_CODE="$(getprop ro.product.device)"
  SYSTEM_DEVICE_FEATURES_PATH=/system/product/etc/device_features/${DEVICE_CODE}.xml
  MODULE_DEVICE_FEATURES_PATH="$1"/system/product/etc/device_features/${DEVICE_CODE}.xml

  # 移除旧版补丁文件
  rm -rf "$MODULE_DEVICE_FEATURES_PATH"

  # 复制系统内配置到模块内
  cp -f "$SYSTEM_DEVICE_FEATURES_PATH" "$MODULE_DEVICE_FEATURES_PATH"
}

patch_support_video_dfps() {
  DEVICE_CODE="$(getprop ro.product.device)"
  SYSTEM_DEVICE_FEATURES_PATH=/system/product/etc/device_features/${DEVICE_CODE}.xml
  MODULE_DEVICE_FEATURES_PATH="$1"/system/product/etc/device_features/${DEVICE_CODE}.xml
  if [[ -f "$MODULE_DEVICE_FEATURES_PATH" ]]; then
    # 解锁视频工具箱智能刷新率
    sed -i "$(awk '/<\/features>/{print NR-0; exit}' $MODULE_DEVICE_FEATURES_PATH)i \    <bool name=\"support_video_dfps\">true</bool>" $MODULE_DEVICE_FEATURES_PATH
  fi
}

patch_eyecare_mode() {
  DEVICE_CODE="$(getprop ro.product.device)"
  SYSTEM_DEVICE_FEATURES_PATH=/system/product/etc/device_features/${DEVICE_CODE}.xml
  MODULE_DEVICE_FEATURES_PATH="$1"/system/product/etc/device_features/${DEVICE_CODE}.xml
  if [[ -f "$MODULE_DEVICE_FEATURES_PATH" ]]; then
    # 节律护眼
    sed -i "$(awk '/<\/features>/{print NR-0; exit}' $MODULE_DEVICE_FEATURES_PATH)i \    <integer name=\"default_eyecare_mode\">2</integer>" $MODULE_DEVICE_FEATURES_PATH
  fi
}

patch_celluar_shared() {

  if [[ ! -d "$1"/system/product/media/theme/default/ ]]; then
    mkdir -p "$1"/system/product/media/theme/default/
  fi

  # 启用通信共享
  cp -rf "$1"/common/celluar_shared/* "$1"/system/product/media/theme/default/
}


patch_perfinit_bdsize_zram() {
  DEVICE_CODE="$(getprop ro.product.device)"
  SYSTEM_PERFINIT_BDSIZE_ZRAM_PATH=/system/system_ext/etc/perfinit_bdsize_zram.conf
  MODULE_PERFINIT_BDSIZE_ZRAM_PATH="$1"/system/system_ext/etc/perfinit_bdsize_zram.conf
  JQ_UTILS="$1"/common/utils/jq

  if [[ ! -d "$1"/system/system_ext/etc/ ]]; then
    mkdir -p "$1"/system/system_ext/etc/
  fi

  # 移除旧版补丁文件
  rm -rf "$MODULE_PERFINIT_BDSIZE_ZRAM_PATH"

  # 复制系统内配置到模块内
  cp -f "$SYSTEM_PERFINIT_BDSIZE_ZRAM_PATH" "$MODULE_PERFINIT_BDSIZE_ZRAM_PATH"
}

patch_zram_config() {
    MODULE_PERFINIT_BDSIZE_ZRAM_PATH="$1"/system/system_ext/etc/perfinit_bdsize_zram.conf
    DEVICE_CODE="$(getprop ro.product.device)"
    MODULE_ZRAM_TEMPLATE="$1"/common/zram_template/"$DEVICE_CODE".json
    $JQ_UTILS '.zram += [input | {product_name, zram_size}]' $MODULE_PERFINIT_BDSIZE_ZRAM_PATH $MODULE_ZRAM_TEMPLATE > temp.json && mv temp.json $MODULE_PERFINIT_BDSIZE_ZRAM_PATH
}

patch_cn_google_services() {
  MODULE_CN_GOOGLE_SERVICES_PATH="$1"/system/product/etc/permissions/

  if [[ ! -d $MODULE_CN_GOOGLE_SERVICES_PATH ]]; then
    mkdir -p $MODULE_CN_GOOGLE_SERVICES_PATH
  fi

  # 移除旧版补丁文件
  rm -rf "$MODULE_DEVICE_FEATURES_PATH"cn.google.services.xml

  cp -rf "$1"/common/cn_google_services/* "$MODULE_CN_GOOGLE_SERVICES_PATH"
}

patch_wild_boost() {
  DEVICE_CODE="$(getprop ro.product.device)"
  SYSTEM_DEVICE_FEATURES_PATH=/system/product/etc/device_features/${DEVICE_CODE}.xml
  MODULE_DEVICE_FEATURES_PATH="$1"/system/product/etc/device_features/${DEVICE_CODE}.xml
  if [[ -f "$MODULE_DEVICE_FEATURES_PATH" ]]; then
    # 游戏工具箱狂暴引擎UI
    sed -i "$(awk '/<\/features>/{print NR-0; exit}' $MODULE_DEVICE_FEATURES_PATH)i \    <bool name=\"support_wild_boost\">true</bool>" $MODULE_DEVICE_FEATURES_PATH
    # 设置、控制中心狂暴引擎UI(安全管家 9.0+)
    sed -i "$(awk '/<\/features>/{print NR-0; exit}' $MODULE_DEVICE_FEATURES_PATH)i \    <bool name=\"support_wild_boost_bat_perf\">true</bool>" $MODULE_DEVICE_FEATURES_PATH
  fi
}

patch_support_aod_fullscreen() {
  DEVICE_CODE="$(getprop ro.product.device)"
  SYSTEM_DEVICE_FEATURES_PATH=/system/product/etc/device_features/${DEVICE_CODE}.xml
  MODULE_DEVICE_FEATURES_PATH="$1"/system/product/etc/device_features/${DEVICE_CODE}.xml
  if [[ -f "$MODULE_DEVICE_FEATURES_PATH" ]]; then
    # 支持全屏AOD
    sed -i "$(awk '/<\/features>/{print NR-0; exit}' $MODULE_DEVICE_FEATURES_PATH)i \    <bool name=\"support_aod_fullscreen\">true</bool>" $MODULE_DEVICE_FEATURES_PATH
  fi
}