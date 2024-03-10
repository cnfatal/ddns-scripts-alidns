# ddns-scripts-alidns

Openwrt Dynamic DNS Client scripts extension for aliyun DNS.

## Install

Install the package with opkg from the pre-built ipk file:

```sh
wget https://github.com/cnfatal/ddns-scripts-alidns/releases/download/1.0.0/ddns-scripts-alidns_1.0.0-1_all.ipk
opkg install ddns-scripts-alidns_1.0.0-1_all.ipk
```

## Usage

Now you can see the new `alidns.com` provider in the `Dynamic DNS` section of the `Service` menu in LuCI.

Fill in the fields with the following information:

| Field | Explanation |
| --- | --- |
| Domain | The domain name to update. eg. `router.example.com` |
| Username | The AccessKey ID of the aliyun account. |
| Password | The AccessKey Secret of the aliyun account. |

## Build

Follow: <https://openwrt.org/docs/guide-developer/helloworld/start>

Open a new workspace and prepare toolchain:

```sh
mkdir -p /tmp/openwrt-build
cd /tmp/openwrt-build
git clone https://git.openwrt.org/openwrt/openwrt.git openwrt
cd openwrt
make distclean
make menuconfig
make toolchain/install
```

Prepare custom feed with our package:

```sh
cd /tmp/openwrt-build
mkdir -p custom-feed && cd custom-feed
git clone https://github.com/cnfatal/ddns-scripts-alidns.git
```

Add custom feed and official packages to openwrt build system:

```sh
cd /tmp/openwrt-build/openwrt
echo "src-link custom /tmp/openwrt-build/custom-feed" >> feeds.conf.default
./scripts/feeds update packages custom
./scripts/feeds install packages custom
```

Build the package:

```sh
cd /tmp/openwrt-build/openwrt
make V=sc package/feeds/packages/net/ddns-scripts/compile
```

The package will be in `/tmp/openwrt-build/openwrt/bin/packages/<arch>/custom/ddns-scripts-alidns_<version>_<arch>.ipk`.
