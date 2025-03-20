cmake_minimum_required(VERSION 3.6.0)

project(asteroid-asteroids
	VERSION 1.0
	DESCRIPTION "The classic Asteroids Arcade Game adapted for AsteroidOS")

find_package(ECM REQUIRED NO_MODULE)
find_package(AsteroidApp REQUIRED)

set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${ASTEROID_MODULE_PATH})

include(FeatureSummary)
include(GNUInstallDirs)
include(ECMFindQmlModule)
include(AsteroidCMakeSettings)
include(AsteroidTranslations)

add_executable(asteroid-asteroids main.cpp resources.qrc)

target_link_libraries(asteroid-asteroids PRIVATE
    AsteroidApp)

install(TARGETS asteroid-asteroids DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES asteroid-asteroids.desktop
        DESTINATION /usr/share/applications/)
install(FILES asteroid-asteroids.svg
        DESTINATION /usr/share/icons/asteroid/)
