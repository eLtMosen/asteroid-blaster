SUMMARY = "The classic Asteroids Arcade Game adapted for AsteroidOS"
HOMEPAGE = "https://github.com/eLtMosen/asteroid-asteroids"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=84dcc94da3adb52b53ae4fa38fe49e5d"

SRC_URI = "git://github.com/eLtMosen/asteroid-asteroids.git;protocol=https;branch=master"
SRCREV = "${AUTOREV}"
PR = "r1"
PV = "+git${SRCPV}"
S = "${WORKDIR}/git"

inherit cmake_qt5 pkgconfig

DEPENDS += "qml-asteroid asteroid-generate-desktop-native qttools-native qtdeclarative-native"
RDEPENDS:${PN} += ""

FILES:${PN} += "/usr/share/translations/"
