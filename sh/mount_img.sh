#!/bin/bash


# UTM 虚拟机utm文件夹扩容脚本
BASE_DIR="/vol1/1000/utm" && \
TMP_DIR="$BASE_DIR/tmp" && \
mkdir -p "$TMP_DIR" && \
chmod 1777 "$TMP_DIR" && \
mountpoint -q /tmp || mount --bind "$TMP_DIR" /tmp && \
export TMPDIR="$TMP_DIR" && \
echo -e "\n✅ UTM 基地扩容成功！\n🌟 临时空间 (/tmp) 当前可用：$(df -h /tmp | awk 'NR==2 {print $4}')\n📂 工作路径：$BASE_DIR"










####################################
# 提取UTM镜像内核并修正配置脚本(精简)
####################################
#!/bin/bash

# --- 配置区 ---
WORKDIR=$(pwd)

echo "🚀 开始本地验证流程..."

# 1. 工具检查 (仅保留必须工具)
for cmd in losetup mount umount dd sed; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ 错误: 本地环境缺少必要工具: $cmd"
        exit 1
    fi
done

# 2. 定位本地 .img 文件
SOURCE_IMG=$(ls -t *rockchip*.img 2>/dev/null | grep -v "rootfs.img" | head -n 1)

if [ -z "$SOURCE_IMG" ]; then
    echo "❌ 错误：未在当前目录找到包含 'rockchip' 的 .img 文件。"
    exit 1
fi

echo "🎯 目标镜像: $SOURCE_IMG"

# 3. 映射分区并提取内核组件
echo "📂 正在映射分区并挂载..."
sudo losetup -D
LOOP_DEV=$(sudo losetup -Pf --show "$SOURCE_IMG")

# 等待设备节点生成
sleep 1

mkdir -p mnt_p1 mnt_new

# 提取 P1 分区的内核和 Initrd
if ! sudo mount -o ro "${LOOP_DEV}p1" mnt_p1 2>/dev/null; then
    echo "❌ 错误：无法挂载 P1 分区。"
    sudo losetup -d "$LOOP_DEV"
    exit 1
fi

KERNEL_PATH=$(sudo find mnt_p1 -name "vmlinuz-*" ! -name "*.old" | sort -V | tail -n 1)
INITRD_PATH=$(sudo find mnt_p1 -name "initrd.img-*" ! -name "*.old" | sort -V | tail -n 1)

RAW_KERNEL=$(basename "$KERNEL_PATH")
RAW_INITRD=$(basename "$INITRD_PATH")

cp "$KERNEL_PATH" "$WORKDIR/$RAW_KERNEL"
cp "$INITRD_PATH" "$WORKDIR/$RAW_INITRD"
echo "✅ 已提取: $RAW_KERNEL 和 $RAW_INITRD"

sudo umount mnt_p1

# 4. 提取 P2 (RootFS)
echo "💾 正在提取 P2 分区到 rootfs.img..."
sudo dd if="${LOOP_DEV}p2" of=rootfs.img bs=1M status=progress
sudo losetup -d "$LOOP_DEV"

# 5. 修改 rootfs.img
echo "🛠️ 正在修改 rootfs.img..."
sudo mount rootfs.img mnt_new

# A. 移除物理硬件冲突服务
sudo rm -f mnt_new/etc/systemd/system/multi-user.target.wants/trim_miniscreen.service
sudo rm -f mnt_new/etc/systemd/system/multi-user.target.wants/trim_wayland.service
echo "✅ 已移除物理机服务"

# B. 修改 fstab (注释掉 /boot 挂载)
if [ -f "mnt_new/etc/fstab" ]; then
    echo "📝 正在修改 fstab (注释 /boot)..."
    sudo sed -i 's/^.*\/boot/#&/' mnt_new/etc/fstab
    # 将 UUID 挂载方式改为直接使用 /dev/vda
    sudo sed -i 's/^UUID=[a-z0-9-]*\s\+\/\s\+btrfs/\/dev\/vda\t\/\tbtrfs/' mnt_new/etc/fstab
    
    echo "--------------------------------------"
    echo "📄 修改后的 fstab 内容如下："
    cat mnt_new/etc/fstab
    echo "--------------------------------------"
else
    echo "⚠️ 警告：未在镜像中找到 /etc/fstab"
fi

# 强制刷新缓存并卸载
sync
sudo umount mnt_new

# 清理临时目录
rm -rf mnt_p1 mnt_new

echo "✨ 处理完成！所有产出均在当前目录。"