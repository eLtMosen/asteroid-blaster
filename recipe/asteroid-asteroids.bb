SUMMARY = "The classic Asteroids Arcade Game adapted for AsteroidOS"
HOMEPAGE = "https://github.com/eLtMosen/asteroid-asteroids"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

SRC_URI = "git://github.com/eLtMosen/asteroid-asteroids.git;protocol=https;branch=main"
SRCREV = "${AUTOREV}"
PR = "r1"
PV = "+git${SRCPV}"
S = "${WORKDIR}/git"

inherit cmake_qt5 pkgconfig

DEPENDS += "qml-asteroid asteroid-generate-desktop-native qttools-native qtdeclarative-native"
RDEPENDS:${PN} += ""

FILES:${PN} += "/usr/share/translations/"
FILES:${PN} += "/usr/share/icons/asteroid/asteroid-asteroids.svg"
