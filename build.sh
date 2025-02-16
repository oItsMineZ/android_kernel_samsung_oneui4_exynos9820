#!/bin/bash

abort()
{
    cd -
    echo "-----------------------------------------------"
    echo "Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit -1
}

unset_flags()
{
    cat << EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the model code of the phone
    -k, --ksu [y/N]        Include KernelSU Next with SuSFS
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m)
            MODEL="$2"
            shift 2
            ;;
        --ksu|-k)
            KSU_OPTION="$2"
            shift 2
            ;;
        *)\
            unset_flags
            exit 1
            ;;
    esac
done

export BUILD_CROSS_COMPILE=$(pwd)/toolchain/aarch64-linux-android-4.9/bin/aarch64-linux-androidkernel-
export BUILD_JOB_NUMBER=`grep -c ^processor /proc/cpuinfo`
RDIR=$(pwd)

# Define specific variables
KERNEL_DEFCONFIG=oitsminez-"$MODEL"_defconfig
case $MODEL in
beyond0lte)
    SOC=9820
    BOARD=SRPRI28A014KU
;;
beyond1lte)
    SOC=9820
    BOARD=SRPRI28B014KU
;;
beyond2lte)
    SOC=9820
    BOARD=SRPRI17C014KU
;;
beyondx)
    SOC=9820
    BOARD=SRPSC04B011KU
;;
d1)
    SOC=9825
    BOARD=SRPSD26B007KU
;;
d1x)
    SOC=9825
    BOARD=SRPSD23A002KU
;;
d2s)
    SOC=9825
    BOARD=SRPSC14B007KU
;;
d2x)
    SOC=9825
    BOARD=SRPSC14C007KU
;;
*)
    unset_flags
    exit
esac

if [ -z $KSU_OPTION ]; then
    read -p "Include Include KernelSU Next with SuSFS (y/N): " KSU_OPTION
fi

if [[ "$KSU_OPTION" == "y" ]]; then
    KSU_NEXT=ksu_next.config
fi

FUNC_BUILD_KERNEL()
{
    echo "Defconfig: "$KERNEL_DEFCONFIG""
    if [ -z "$KSU_NEXT" ]; then
        echo "KSU_NEXT: N"
    else
        echo "KSU_NEXT: $KSU_NEXT"
    fi

    echo " Starting a kernel build using "$KERNEL_DEFCONFIG ""

    if [[ "$SOC" == "9825" ]]; then
        N10=exynos9825.config
    fi

    make -j$BUILD_JOB_NUMBER ARCH=arm64 \
        CROSS_COMPILE=$BUILD_CROSS_COMPILE O=out \
        $KERNEL_DEFCONFIG oitsminez.config $KSU_NEXT $N10 || abort

    make -j$BUILD_JOB_NUMBER ARCH=arm64 \
        CROSS_COMPILE=$BUILD_CROSS_COMPILE O=out || abort

    echo " Finished kernel build"
}

FUNC_BUILD_DTBO()
{
    $RDIR/toolchain/mkdtimg cfg_create $RDIR/build/out/$MODEL/dtb_$SOC.img \
        $RDIR/build/dtconfigs/exynos$SOC.cfg \
        -d $RDIR/out/arch/arm64/boot/dts/exynos

    $RDIR/toolchain/mkdtimg cfg_create $RDIR/build/out/$MODEL/dtbo_$MODEL.img \
        $RDIR/build/dtconfigs/$MODEL.cfg \
        -d $RDIR/out/arch/arm64/boot/dts/samsung
}

FUNC_BUILD_RAMDISK()
{
    rm -f $RDIR/build/AIK/split_img/boot.img-kernel
    cp $RDIR/out/arch/arm64/boot/Image $RDIR/build/AIK/split_img/boot.img-kernel
    echo $BOARD > build/AIK/split_img/boot.img-board

    # This is kinda ugly hack, we could as well touch .placeholder to all of those
    mkdir -p $RDIR/build/AIK/ramdisk/debug_ramdisk
    mkdir -p $RDIR/build/AIK/ramdisk/dev
    mkdir -p $RDIR/build/AIK/ramdisk/mnt
    mkdir -p $RDIR/build/AIK/ramdisk/proc
    mkdir -p $RDIR/build/AIK/ramdisk/sys

    rm -rf $RDIR/build/AIK/ramdisk/fstab.exynos9820
    rm -rf $RDIR/build/AIK/ramdisk/fstab.exynos9825

    cp $RDIR/build/AIK/fstab.exynos$SOC $RDIR/build/AIK/ramdisk/

    cd $RDIR/build/AIK/
    ./repackimg.sh --nosudo
}

FUNC_BUILD_ZIP()
{
    rm -rf $RDIR/build/out/$MODEL/zip
    mkdir -p $RDIR/build/export
    mkdir -p $RDIR/build/out/$MODEL/zip
    mkdir -p $RDIR/build/out/$MODEL/zip/META-INF/com/google/android
    mv $RDIR/build/AIK/image-new.img $RDIR/build/out/$MODEL/boot-patched.img

    # Make recovery flashable package
    cp $RDIR/build/out/$MODEL/boot-patched.img $RDIR/build/out/$MODEL/zip/boot.img
    cp $RDIR/build/out/$MODEL/dtb_exynos$SOC.img $RDIR/build/out/$MODEL/zip/dtb.img
    cp $RDIR/build/out/$MODEL/dtbo_$MODEL.img $RDIR/build/out/$MODEL/zip/dtbo.img
    cp $RDIR/build/updater-script $RDIR/build/out/$MODEL/zip/META-INF/com/google/android/
    cp $RDIR/build/update-binary $RDIR/build/out/$MODEL/zip/META-INF/com/google/android/
    cd $RDIR/build/out/$MODEL/zip

    if [ "$SOC" == "9825" ]; then
        version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/exynos9825.config | cut -d '"' -f 2)
    else
        version=$(grep -o 'CONFIG_LOCALVERSION="[^"]*"' arch/arm64/configs/oitsminez.config | cut -d '"' -f 2)
    fi

    version=${version:1}
    DATE=`date +"%d-%m-%Y_%H-%M-%S"`    
    NAME="$version"-"$MODEL"-KSU-NEXT-v2+SuSFS-"$DATE".zip

    zip -r ../"$NAME" .
    rm -rf $RDIR/build/out/$MODEL/zip
    mv $RDIR/build/out/$MODEL/"$NAME" $RDIR/build/export/"$NAME"
    cd $RDIR/build/export
}

# MAIN FUNCTION
rm -rf ./build.log
(
	START_TIME=`date +%s`

	echo "Preparing the build environment..."

	FUNC_BUILD_KERNEL
	FUNC_BUILD_DTBO
	FUNC_BUILD_RAMDISK
	FUNC_BUILD_ZIP

	END_TIME=`date +%s`

	let "ELAPSED_TIME=$END_TIME-$START_TIME"
	echo "Total compile time was $ELAPSED_TIME seconds"

) 2>&1	| tee -a ./build.log