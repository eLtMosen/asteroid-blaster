/*
 * Copyright (C) 2025 - Timo Könnecke <github.com/eLtMosen>
 *
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 2.1 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.15
import QtSensors 5.15
import Nemo.Ngf 1.0
import Nemo.Configuration 1.0
import QtQuick.Shapes 1.15
import org.asteroid.controls 1.0
import Nemo.KeepAlive 1.1

Item {
    id: root
    anchors.fill: parent
    visible: true

    // --- Game Mechanics ---
    property bool calibrating: true
    property int calibrationTimer: 4
    property bool debugMode: false
    property bool gameOver: false
    property int level: 1
    property bool paused: false
    property int score: 0
    property int shield: 3
    property real dimsFactor: Dims.l(100) / 100
    property var activeShots: []  // Track autofire shots
    property var activeAsteroids: []  // Track active asteroids
    property real lastFrameTime: 0
    property real baselineX: 0  // Calibration baseline for accelerometer
    property real smoothedX: 0  // Smoothed accelerometer reading
    property real smoothingFactor: 0.5  // Smoothing factor for responsiveness
    property real rotationSpeed: 60  // Degrees per second
    property real playerRotation: 0  // Current rotation of player
    property int lastShieldAward: 0  // Track the last score threshold for shield award
    property int initialAsteroidsToSpawn: 5  // Starting number for level 1
    property int asteroidsSpawned: 0  // Track how many have been spawned this level
    property bool afterBurnerActive: false  // Is afterburner currently in use?
    property real afterBurnerTimeLeft: 0  // Time remaining in boost (seconds)
    property real afterBurnerCooldown: 0  // Cooldown time left (seconds)
    property real boostDistance: dimsFactor * 40  // Max distance from center
    property real centerX: root.width / 2  // Center position for return
    property real centerY: root.height / 2
    property real boostProgress: 0  // 0 to 1 over 500ms for acceleration

    ConfigurationValue {
        id: highScore
        key: "/asteroids/highScore"
        defaultValue: 0
    }

    ConfigurationValue {
        id: highLevel
        key: "/asteroids/highLevel"
        defaultValue: 1
    }

    NonGraphicalFeedback {
        id: feedback
        event: "press"
    }

    onGameOverChanged: {
        if (gameOver) {
            if (score > highScore.value) {
                highScore.value = score
            }
            if (level > highLevel.value) {
                highLevel.value = level
            }
        }
    }

    Timer {
        id: gameTimer
        interval: 16
        running: !gameOver && !calibrating
        repeat: true
        property real lastFps: 60
        property var fpsHistory: []
        property real lastFpsUpdate: 0
        property real lastGraphUpdate: 0

        onTriggered: {
            var currentTime = Date.now()
            var deltaTime = lastFrameTime > 0 ? (currentTime - lastFrameTime) / 1000 : 0.016
            if (deltaTime > 0.033) deltaTime = 0.033  // Cap at ~30 FPS
            lastFrameTime = currentTime
            updateGame(deltaTime)

            if (!paused) {
                var rawX = accelerometer.reading.x
                smoothedX = smoothedX + smoothingFactor * (rawX - smoothedX)
                var deltaX = (smoothedX - baselineX) * -2  // Invert for intuitive tilt
                playerRotation += deltaX * rotationSpeed * deltaTime
                playerRotation = (playerRotation + 360) % 360  // Normalize to 0-360
            }

            var currentFps = deltaTime > 0 ? 1 / deltaTime : 60
            lastFps = currentFps
            if (debugMode && currentTime - lastFpsUpdate >= 500) {
                lastFpsUpdate = currentTime
                fpsDisplay.text = "FPS: " + Math.round(currentFps)
            }
            if (debugMode && currentTime - lastGraphUpdate >= 500) {
                lastGraphUpdate = currentTime
                var tempHistory = fpsHistory.slice()
                tempHistory.push(currentFps)
                if (tempHistory.length > 10) tempHistory.shift()
                fpsHistory = tempHistory
            }
        }
    }

    Timer {
        id: calibrationCountdownTimer
        interval: 1000
        running: calibrating
        repeat: true
        onTriggered: {
            calibrationTimer--
            if (calibrationTimer <= 0) {
                baselineX = accelerometer.reading.x
                smoothedX = baselineX
                calibrating = false
                feedback.play()
            }
        }
    }

    Timer {
        id: autoFireTimer
        interval: 150
        running: !gameOver && !calibrating && !paused
        repeat: true
        onTriggered: {
            var rad = playerRotation * Math.PI / 180
            var shotX = playerContainer.x + playerHitbox.x + playerHitbox.width / 2 - dimsFactor * 0.5
            var shotY = playerContainer.y + playerHitbox.y + playerHitbox.height / 2 - dimsFactor * 2.5
            var offsetX = Math.sin(rad) * (dimsFactor * 5)
            var offsetY = -Math.cos(rad) * (dimsFactor * 5)
            var shot = autoFireShotComponent.createObject(gameArea, {
                "x": shotX + offsetX,
                "y": shotY + offsetY,
                "directionX": Math.sin(rad),
                "directionY": -Math.cos(rad),
                "rotation": playerRotation
            })
            activeShots.push(shot)
        }
    }

    Timer {
        id: asteroidSpawnTimer
        interval: Math.max(500, 3000 - (level - 1) * 131)  // From 3000ms to 500ms
        running: !gameOver && !calibrating && !paused && asteroidsSpawned < initialAsteroidsToSpawn
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            spawnLargeAsteroid()
            asteroidsSpawned++
            if (asteroidsSpawned >= initialAsteroidsToSpawn) {
                stop()
            }
        }
    }

    Component {
        id: explosionParticleComponent
        ShaderEffect {
            id: explosion
            property real asteroidSize: dimsFactor * 18  // Default, overridden by creation
            property string explosionColor: "default"  // "default" for fiery colors, "shield" for blueish explosion
            property real sizeMultiplier: {
                if (asteroidSize === dimsFactor * 20) return 1.0  // Large: no change
                if (asteroidSize === dimsFactor * 12) return 1.25  // Mid: +1/4
                if (asteroidSize === dimsFactor * 6) return 1.333  // Small: +1/3
                return 1.0  // Fallback
            }
            width: Math.round(asteroidSize * 2.33 * sizeMultiplier)
            height: Math.round(asteroidSize * 2.33 * sizeMultiplier)
            z: 0  // Drop below everything: background (-1), player (1), shots (2), asteroids (3), explosions (4), score (6)

            property real time: 0.0
            property color baseColor: explosionColor === "shield" ? "#3399FF" : "#FFAA33"  // Fiery orange/yellow

            layer.enabled: true
            layer.effect: ShaderEffectSource {
                sourceItem: explosion
                hideSource: true
            }

            NumberAnimation on time {
                from: 0.0
                to: 1.0
                duration: 1000
                running: true
                easing.type: Easing.Linear  // Still testing true duration
                onRunningChanged: {
                    if (!running && time >= 1.0) {
                        explosion.destroy()
                    }
                }
            }

            vertexShader: "
                uniform highp mat4 qt_Matrix;
                attribute highp vec4 qt_Vertex;
                attribute highp vec2 qt_MultiTexCoord0;
                varying highp vec2 coord;
                void main() {
                    coord = qt_MultiTexCoord0;
                    gl_Position = qt_Matrix * qt_Vertex;
                }
            "

            fragmentShader: "
                varying highp vec2 coord;
                uniform highp float time;
                uniform highp vec3 baseColor;
                uniform highp float qt_Opacity;

                // Simple pseudo-random noise function
                highp float noise(highp vec2 p) {
                    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
                }

                void main() {
                    highp vec2 uv = coord - vec2(0.5);  // Center the effect
                    highp float dist = length(uv);
                    highp float fade = 1.0 - time;  // Linear fade
                    highp vec3 color = vec3(0.0);
                    highp float totalAlpha = 0.0;

                    // Starburst effect with radial streaks
                    for (int i = 0; i < 16; i++) {  // More streaks
                        highp float angle = float(i) * 0.3927 + noise(vec2(float(i), time)) * 0.4;  // 22.5° steps + jitter
                        highp float speed = 0.8 + noise(vec2(float(i) + 1.0, time)) * 0.4;  // Speed: 0.8 to 1.2
                        highp float radius = speed * time;
                        highp vec2 particlePos = vec2(cos(angle), sin(angle)) * radius;

                        // Swirl effect for slight rotation
                        highp float swirl = time * 3.0 * (noise(vec2(float(i), 0.0)) - 0.5);
                        particlePos += vec2(cos(swirl), sin(swirl)) * 0.1;

                        highp float particleDist = length(uv - particlePos);
                        highp float particleSize = 0.08 * (1.0 - time * 0.3);  // Larger particles
                        if (particleDist < particleSize) {
                            highp float intensity = 1.0 - (particleDist / particleSize);
                            color += mix(vec3(1.0, 0.6, 0.2), baseColor, time) * intensity * intensity * fade;  // White-hot to orange
                            totalAlpha += intensity * fade;
                        }
                    }

                    // Glowing core that fades to transparency
                    highp float coreDist = dist * (1.0 + time);
                    if (coreDist < 0.3) {  // Larger core
                        highp float coreIntensity = 1.0 - (coreDist / 0.3);
                        color += mix(vec3(1.0, 0.9, 0.6), baseColor, time) * coreIntensity * fade * 0.9;
                        totalAlpha += coreIntensity * fade;
                    }

                    // Ensure visibility on black background by boosting brightness
                    color = clamp(color * 2.0, vec3(0.0), vec3(1.0));  // Increase brightness

                    gl_FragColor = vec4(color, totalAlpha * qt_Opacity);
                }
            "

            property variant uniforms: { "baseColor": Qt.vector3d(baseColor.r, baseColor.g, baseColor.b) }
        }
    }

    Component {
        id: autoFireShotComponent
        Rectangle {
            width: dimsFactor * 1
            height: dimsFactor * 4
            color: "#00FFFF"  // Was #800080 (purple), now cyan
            z: 2
            visible: true
            property real speed: 8
            property real directionX: 0
            property real directionY: -1
            rotation: playerRotation
        }
    }

    Component {
        id: scoreParticleComponent
        Text {
            id: particle
            color: "#00FFFF"  // Default cyan, overridden by creation
            font {
                pixelSize: dimsFactor * 8
                family: "Teko"
                styleName: "Medium"
            }
            z: 6  // Above explosions (0)
            opacity: 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 2000  // Doubled from 1000ms
                    easing.type: Easing.InOutQuad  // Slower fade-out, holds opacity longer
                    onRunningChanged: {
                        if (!running && opacity === 0) {
                            particle.destroy()
                        }
                    }
                }
            }

            Component.onCompleted: {
                opacity = 0
            }
        }
    }

    Component {
        id: asteroidComponent
        Shape {
            id: asteroid
            property real size: dimsFactor * 20
            property real speed: {
                if (asteroidSize === "large") return 0.3  // Was 0.24
                if (asteroidSize === "mid") return 0.4   // Was 0.36
                if (asteroidSize === "small") return 0.6 // Was 0.52
                return 2                          // Fallback
            }
            property real directionX: 0
            property real directionY: 0
            property string asteroidSize: "large"  // "large", "mid", "small"
            property real rotationSpeed: (Math.random() < 0.5 ? -1 : 1) * (10 + Math.random() * 2 - 1)  // 5-15 deg/s with ±10% variance
            width: size
            height: size
            z: 3

            // Generate spiky asteroid points with more variance in radius and extra points
            property var asteroidPoints: {
                var basePoints = Math.floor(5 + Math.random() * 3); // 5-7 base points
                var pointsArray = [];
                var centerX = size / 2;
                var centerY = size / 2;

                for (var i = 0; i < basePoints; i++) {
                    var baseAngle = (i / basePoints) * 2 * Math.PI;
                    var angleVariation = Math.random() * 0.2 - 0.1;
                    var angle = baseAngle + angleVariation;
                    var isSpike = Math.random() < 0.7;
                    var minRadius = isSpike ? size * 0.35 : size * 0.25;
                    var maxRadius = isSpike ? size * 0.48 : size * 0.32;
                    var radius = minRadius + Math.random() * (maxRadius - minRadius);
                    var x = centerX + radius * Math.cos(angle);
                    var y = centerY + radius * Math.sin(angle);
                    pointsArray.push({x: x, y: y});

                    if (Math.random() < 0.3 && i < basePoints - 1) {
                        var midAngle = baseAngle + (1 / basePoints) * Math.PI + (Math.random() * 0.2 - 0.1);
                        var midRadius = size * (0.2 + Math.random() * 0.15);
                        var midX = centerX + midRadius * Math.cos(midAngle);
                        var midY = centerY + midRadius * Math.sin(midAngle);
                        pointsArray.push({x: midX, y: midY});
                    }
                }
                return pointsArray;
            }

            rotation: 0  // Initial rotation
            NumberAnimation on rotation {
                running: !paused && !gameOver && !calibrating
                loops: Animation.Infinite
                from: 0
                to: 360 * (rotationSpeed < 0 ? -1 : 1)  // Clockwise or counterclockwise
                duration: Math.abs(360 / rotationSpeed) * 800  // Time for one full rotation in ms
            }

            ShapePath {
                strokeWidth: dimsFactor * 1
                strokeColor: "white"
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                startX: asteroid.asteroidPoints[0].x
                startY: asteroid.asteroidPoints[0].y

                PathPolyline {
                    path: {
                        var pathPoints = [];
                        for (var i = 0; i < asteroid.asteroidPoints.length; i++) {
                            pathPoints.push(Qt.point(asteroid.asteroidPoints[i].x, asteroid.asteroidPoints[i].y));
                        }
                        pathPoints.push(Qt.point(asteroid.asteroidPoints[0].x, asteroid.asteroidPoints[0].y));
                        return pathPoints;
                    }
                }
            }

            function split() {
                if (asteroidSize === "large" && activeAsteroids.filter(a => a.asteroidSize === "mid").length < 10) {
                    spawnSplitAsteroids("mid", dimsFactor * 12, 2, x, y, directionX, directionY);  // Mid size was 10, +20% ≈ 12
                } else if (asteroidSize === "mid" && activeAsteroids.filter(a => a.asteroidSize === "small").length < 20) {
                    spawnSplitAsteroids("small", dimsFactor * 6, 2, x, y, directionX, directionY);  // Small size was 5, +20% ≈ 6
                }
                destroyAsteroid(this);
            }
        }
    }

    Item {
        id: gameArea
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "black"
            layer.enabled: true
            clip: true
            z: -1  // Ensure background is below all content
        }

        Item {
            id: gameContent
            anchors.fill: parent

            Rectangle {
                id: scorePerimeter
                width: dimsFactor * 55
                height: dimsFactor * 55
                radius: dimsFactor * 27.5
                color: "#010A13"
                border.color: "#0860C4"
                border.width: 1
                anchors.centerIn: parent
                z: 0
                visible: !calibrating

                Behavior on border.color {
                    ColorAnimation {
                        duration: 1000
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: 1000
                        easing.type: Easing.OutQuad
                    }
                }
            }

            Timer {
                id: perimeterFlashTimer
                interval: 100
                repeat: false
                onTriggered: {
                    scorePerimeter.border.color = "#0860C4"  // Fade back outline
                    scorePerimeter.color = "#010A13"  // Fade back fill
                }
            }

            Item {
                id: playerContainer
                x: root.width / 2 - player.width / 2 + dimsFactor * 5
                y: root.height / 2 - player.height / 2 + dimsFactor * 5
                z: 1
                visible: !calibrating

                Image {
                    id: player
                    width: dimsFactor * 10
                    height: dimsFactor * 10
                    source: "file:///usr/share/asteroid-launcher/watchfaces-img/asteroid-logo.svg"
                    anchors.centerIn: parent
                    rotation: playerRotation
                }

                Shape {
                    id: playerHitbox
                    width: dimsFactor * 10
                    height: dimsFactor * 10
                    anchors.centerIn: parent
                    visible: false
                    rotation: playerRotation

                    ShapePath {
                        strokeWidth: -1
                        fillColor: "transparent"
                        startX: dimsFactor * 5; startY: 0
                        PathLine { x: dimsFactor * 10; y: dimsFactor * 5 }
                        PathLine { x: dimsFactor * 5; y: dimsFactor * 10 }
                        PathLine { x: 0; y: dimsFactor * 5 }
                        PathLine { x: dimsFactor * 5; y: 0 }
                    }
                }

                Shape {
                    id: shieldHitbox
                    width: dimsFactor * 14
                    height: dimsFactor * 14
                    anchors.centerIn: parent
                    visible: shield > 0
                    rotation: playerRotation

                    ShapePath {
                        strokeWidth: 2
                        strokeColor: "#DD1155"
                        fillColor: "transparent"
                        startX: dimsFactor * 7; startY: 0
                        PathLine { x: dimsFactor * 14; y: dimsFactor * 7 }
                        PathLine { x: dimsFactor * 7; y: dimsFactor * 14 }
                        PathLine { x: 0; y: dimsFactor * 7 }
                        PathLine { x: dimsFactor * 7; y: 0 }
                    }
                }
            }

            Text {
                id: levelNumber
                text: level
                color: "#F9DC5C"
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                    styleName: "SemiBold"
                }
                anchors {
                    top: root.top
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !calibrating
            }

            Text {
                id: scoreText
                text: score
                color: "#00FFFF"
                font {
                    pixelSize: dimsFactor * 13
                    family: "Teko"
                    styleName: "Light"
                }
                anchors {
                    bottom: shieldText.top
                    bottomMargin: -dimsFactor * 8
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !calibrating
            }

            Text {
                id: shieldText
                text: shield
                color: shield > 0 ? "#DD1155" : "white"  // Red when active, white when 0
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                    styleName: "SemiBold"
                }
                anchors {
                    bottom: parent.bottom
                    bottomMargin: -dimsFactor * 6
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !calibrating
            }

            Item {
                id: calibrationContainer
                anchors.fill: parent
                visible: calibrating

                Text {
                    text: "v1.0\nAsteroid Blaster"
                    color: "#dddddd"
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 0.6
                    font {
                        family: "Teko"
                        pixelSize: dimsFactor * 16
                        styleName: "Medium"
                    }
                    anchors {
                        bottom: calibrationText.top
                        bottomMargin: dimsFactor * 10
                        horizontalCenter: parent.horizontalCenter
                    }
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    id: calibrationText
                    anchors {
                        top: parent.verticalCenter
                        horizontalCenter: parent.horizontalCenter
                    }
                    spacing: dimsFactor * 1
                    Text {
                        text: "Calibrating"
                        color: "white"
                        font.pixelSize: dimsFactor * 9
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: "Hold your watch comfy"
                        color: "white"
                        font.pixelSize: dimsFactor * 6
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: calibrationTimer + "s"
                        color: "white"
                        font.pixelSize: dimsFactor * 9
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: calibrating
                    onClicked: {
                        baselineX = accelerometer.reading.x
                        smoothedX = baselineX
                        calibrating = false
                        feedback.play()
                    }
                }
            }

            Text {
                id: pauseText
                text: "Paused"
                color: "white"
                font {
                    pixelSize: dimsFactor * 22
                    family: "Teko"
                }
                anchors.centerIn: parent
                opacity: 0
                z: 2
                visible: !gameOver && !calibrating
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.InOutQuad
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !gameOver && !calibrating
                    onClicked: {
                        paused = !paused
                        pauseText.opacity = paused ? 1.0 : 0.0
                    }
                }
            }

            MouseArea {
                id: afterBurnerTrigger
                anchors {
                    left: parent.left
                    right: parent.right
                    top: pauseText.bottom
                    bottom: parent.bottom
                }
                enabled: !gameOver && !calibrating && !paused && afterBurnerCooldown <= 0
                onPressed: {
                    if (!afterBurnerActive) {
                        afterBurnerActive = true
                        afterBurnerTimeLeft = 2.0  // Max 2 seconds
                        feedback.play()
                    }
                }
                onReleased: {
                    if (afterBurnerActive) {
                        afterBurnerActive = false
                        afterBurnerCooldown = 10.0  // 10s cooldown
                    }
                }
            }

            Text {
                id: fpsDisplay
                text: "FPS: 60"
                color: "white"
                opacity: 0.5
                font.pixelSize: dimsFactor * 10
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: fpsGraph.top
                }
                visible: debugMode && !gameOver && !calibrating
            }

            Rectangle {
                id: fpsGraph
                width: dimsFactor * 30
                height: dimsFactor * 10
                color: "#00000000"
                opacity: 0.5
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: debugToggle.top
                    topMargin: dimsFactor * 3
                }
                visible: debugMode && !gameOver && !calibrating
                // ... fpsGraph content unchanged ...
            }

            Text {
                id: debugToggle
                text: "Debug"
                color: "white"
                opacity: debugMode ? 1 : 0.5
                font {
                    pixelSize: dimsFactor * 10
                    bold: debugMode
                }
                anchors {
                    bottom: pauseText.top
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: dimsFactor * 4
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.InOutQuad
                    }
                }
                visible: paused && !gameOver && !calibrating
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        debugMode = !debugMode
                    }
                }
            }
        }

        Item {
            id: gameOverContainer
            anchors.fill: parent
            visible: gameOver
            z: 10

            Text {
                id: gameOverText
                text: "Game Over"
                color: "white"
                font {
                    pixelSize: dimsFactor * 20
                    family: "Teko"
                    styleName: "Medium"
                }
                anchors {
                    bottom: scoreOverText.top
                    bottomMargin: -dimsFactor * 8
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Text {
                id: scoreOverText
                text: "Score: " + score + "\nLevel: " + level
                horizontalAlignment: Text.AlignHCenter
                color: "white"
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 0.6
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                }
                anchors {
                    bottom: parent.verticalCenter
                    bottomMargin: dimsFactor * 1
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Text {
                id: highScoreOverText
                text: "Highscore: " + highScore.value + "\nLevel: " + highLevel.value
                horizontalAlignment: Text.AlignHCenter
                color: "white"
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 0.6
                font {
                    pixelSize: dimsFactor * 12
                    family: "Teko"
                }
                anchors {
                    top: parent.verticalCenter
                    topMargin: dimsFactor * 1
                    horizontalCenter: parent.horizontalCenter
                }
            }

            Rectangle {
                id: tryAgainButton
                width: dimsFactor * 50
                height: dimsFactor * 20
                radius: dimsFactor * 2
                color: "#40ffffff"
                anchors {
                    top: highScoreOverText.bottom
                    topMargin: dimsFactor * 6
                    horizontalCenter: parent.horizontalCenter
                }

                Text {
                    text: "Try Again"
                    color: "white"
                    font {
                        pixelSize: dimsFactor * 10
                        family: "Teko"
                        styleName: "SemiBold"
                    }
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        restartGame()
                    }
                }
            }

            // Save highscore when game over screen appears
            Component.onCompleted: {
                if (score > highScore.value) {
                    highScore.value = score
                }
                if (level > highLevel.value) {
                    highLevel.value = level
                }
            }
        }

        Accelerometer {
            id: accelerometer
            active: true
        }
    }

    function updateGame(deltaTime) {
        // Update shots and check collisions with asteroids
        for (var i = activeShots.length - 1; i >= 0; i--) {
            var shot = activeShots[i]
            if (shot) {
                shot.x += shot.directionX * shot.speed * deltaTime * 60
                shot.y += shot.directionY * shot.speed * deltaTime * 60
                if (shot.y <= -shot.height || shot.y >= root.height || shot.x <= -shot.width || shot.x >= root.width) {
                    shot.destroy()
                    activeShots.splice(i, 1)
                } else {
                    var shotHit = false
                    for (var j = activeAsteroids.length - 1; j >= 0; j--) {
                        var asteroid = activeAsteroids[j]
                        if (checkShotAsteroidCollision(shot, asteroid)) {
                            handleShotAsteroidCollision(shot, asteroid)
                            shotHit = true
                            break
                        }
                    }
                    if (shotHit) {
                        shot.destroy()
                        activeShots.splice(i, 1)
                    }
                }
            }
        }

        // Update asteroids only if not paused
        if (!paused) {
            for (var j = activeAsteroids.length - 1; j >= 0; j--) {
                var asteroid = activeAsteroids[j]
                if (asteroid) {
                    asteroid.x += asteroid.directionX * asteroid.speed * deltaTime * 60
                    asteroid.y += asteroid.directionY * asteroid.speed * deltaTime * 60

                    // Screen wrapping logic
                    if (asteroid.x > root.width) {
                        asteroid.x = -asteroid.width
                    } else if (asteroid.x + asteroid.width < 0) {
                        asteroid.x = root.width
                    }
                    if (asteroid.y > root.height) {
                        asteroid.y = -asteroid.height
                    } else if (asteroid.y + asteroid.height < 0) {
                        asteroid.y = root.height
                    }

                    // Player-asteroid collision check with proximity filter
                    var playerCenterX = playerContainer.x + playerHitbox.width / 2
                    var playerCenterY = playerContainer.y + playerHitbox.height / 2
                    var asteroidCenterX = asteroid.x + asteroid.width / 2
                    var asteroidCenterY = asteroid.y + asteroid.height / 2
                    var proximityRange = dimsFactor * 20  // Small area around player
                    var dx = Math.abs(playerCenterX - asteroidCenterX)
                    var dy = Math.abs(playerCenterY - asteroidCenterY)
                    if (dx < proximityRange && dy < proximityRange) {
                        if (checkPlayerAsteroidCollision(playerHitbox, asteroid)) {
                            handlePlayerAsteroidCollision(asteroid)
                        }
                    }
                }
            }

            // Afterburner logic
            if (afterBurnerActive && afterBurnerTimeLeft > 0) {
                afterBurnerTimeLeft -= deltaTime
                boostProgress = Math.min(boostProgress + deltaTime / 0.5, 1.0)
                var maxBoostSpeed = dimsFactor * 25  // Was 50, halved again
                var boostSpeed = maxBoostSpeed * boostProgress

                // Find nearest asteroid for evasion direction
                var nearestAsteroid = null
                var minDistance = Infinity
                var playerCenterX = playerContainer.x + playerHitbox.width / 2
                var playerCenterY = playerContainer.y + playerHitbox.height / 2
                for (var k = 0; k < activeAsteroids.length; k++) {
                    var ast = activeAsteroids[k]
                    var astCenterX = ast.x + ast.width / 2
                    var astCenterY = ast.y + ast.height / 2
                    var dx = astCenterX - playerCenterX
                    var dy = astCenterY - playerCenterY
                    var distance = Math.sqrt(dx * dx + dy * dy)
                    if (distance < minDistance) {
                        minDistance = distance
                        nearestAsteroid = ast
                    }
                }

                // Calculate evasion direction (away from nearest asteroid)
                var dx, dy
                if (nearestAsteroid) {
                    var astCenterX = nearestAsteroid.x + nearestAsteroid.width / 2
                    var astCenterY = nearestAsteroid.y + nearestAsteroid.height / 2
                    dx = playerCenterX - astCenterX
                    dy = playerCenterY - astCenterY
                    var mag = Math.sqrt(dx * dx + dy * dy)
                    if (mag > 0) {
                        dx /= mag
                        dy /= mag
                    } else {
                        dx = 0
                        dy = -1  // Default up if no direction
                    }
                } else {
                    dx = 0
                    dy = -1  // Default up if no asteroids
                }

                // Apply boost
                var newX = playerContainer.x + dx * boostSpeed * deltaTime
                var newY = playerContainer.y + dy * boostSpeed * deltaTime
                var distX = newX - centerX
                var distY = newY - centerY
                var distance = Math.sqrt(distX * distX + distY * distY)
                if (distance <= boostDistance) {
                    playerContainer.x = newX
                    playerContainer.y = newY
                }

                if (afterBurnerTimeLeft <= 0) {
                    afterBurnerActive = false
                    afterBurnerCooldown = 10.0
                    boostProgress = 0
                }
            } else if (!afterBurnerActive) {
                // Drift back to center
                var returnSpeed = dimsFactor * 20
                var dx = centerX - playerContainer.x
                var dy = centerY - playerContainer.y
                var distance = Math.sqrt(dx * dx + dy * dy)
                if (distance > dimsFactor * 5) {
                    var moveX = (dx / distance) * returnSpeed * deltaTime
                    var moveY = (dy / distance) * returnSpeed * deltaTime
                    playerContainer.x += moveX
                    playerContainer.y += moveY
                } else {
                    playerContainer.x = centerX
                    playerContainer.y = centerY
                }
                boostProgress = 0
            }

            // Update cooldown
            if (afterBurnerCooldown > 0) {
                afterBurnerCooldown -= deltaTime
                if (afterBurnerCooldown < 0) afterBurnerCooldown = 0
            }
        }

        // Separate collision pass for asteroid-asteroid collisions (only if not paused)
        if (!paused) {
            for (var j = 0; j < activeAsteroids.length; j++) {
                var asteroid1 = activeAsteroids[j]
                if (!asteroid1) continue
                for (var k = j + 1; k < activeAsteroids.length; k++) {
                    var asteroid2 = activeAsteroids[k]
                    if (checkCollision(asteroid1, asteroid2)) {
                        handleAsteroidCollision(asteroid1, asteroid2)
                    }
                }
            }
        }
    }

    function spawnLargeAsteroid() {
        var size = dimsFactor * 18
        var spawnSide = Math.floor(Math.random() * 4)  // 0: top, 1: right, 2: bottom, 3: left
        var spawnX, spawnY, targetX, targetY
        switch (spawnSide) {
            case 0: // Top
                spawnX = Math.random() * root.width
                spawnY = -size
                targetX = Math.random() * root.width
                targetY = root.height + size
                break
            case 1: // Right
                spawnX = root.width + size
                spawnY = Math.random() * root.height
                targetX = -size
                targetY = Math.random() * root.height
                break
            case 2: // Bottom
                spawnX = Math.random() * root.width
                spawnY = root.height + size
                targetX = Math.random() * root.width
                targetY = -size
                break
            case 3: // Left
                spawnX = -size
                spawnY = Math.random() * root.height
                targetX = root.width + size
                targetY = Math.random() * root.height
                break
        }
        var dx = targetX - spawnX
        var dy = targetY - spawnY
        var mag = Math.sqrt(dx * dx + dy * dy)
        var asteroid = asteroidComponent.createObject(gameArea, {
            "x": spawnX,
            "y": spawnY,
            "size": size,
            "directionX": dx / mag,
            "directionY": dy / mag,
            "asteroidSize": "large"
        })
        activeAsteroids.push(asteroid)
    }

    function spawnSplitAsteroids(sizeType, size, count, x, y, directionX, directionY) {
        var rad = Math.atan2(directionY, directionX)
        for (var i = 0; i < count; i++) {
            var offsetAngle = (i === 0 ? -1 : 1) * 45 * Math.PI / 180  // 45° left or right
            var newRad = rad + offsetAngle
            var newDirX = Math.cos(newRad)
            var newDirY = Math.sin(newRad)
            var asteroid = asteroidComponent.createObject(gameArea, {
                "x": x,
                "y": y,
                "size": size,
                "directionX": newDirX,
                "directionY": newDirY,
                "asteroidSize": sizeType
            })
            activeAsteroids.push(asteroid)
        }
    }

    function destroyAsteroid(asteroid) {
        var index = activeAsteroids.indexOf(asteroid)
        if (index !== -1) {
            activeAsteroids.splice(index, 1)
            asteroid.destroy()
            checkLevelComplete()
        }
    }

    function checkLevelComplete() {
        if (activeAsteroids.length === 0 && asteroidsSpawned >= initialAsteroidsToSpawn) {
            level++
            initialAsteroidsToSpawn = 4 + level
            asteroidsSpawned = 0
            spawnLargeAsteroid()  // Spawn first asteroid of new level immediately
            asteroidsSpawned++
            asteroidSpawnTimer.restart()  // Then continue with timer
        }
    }

    function pointInPolygon(x, y, points) {
        // Ray-casting algorithm to determine if point (x, y) is inside polygon defined by points
        var inside = false
        for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
            var xi = points[i].x, yi = points[i].y
            var xj = points[j].x, yj = points[j].y
            var intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)
            if (intersect) inside = !inside
        }
        return inside
    }

    function checkShotAsteroidCollision(shot, asteroid) {
        // Define shot's rectangular bounds in global coordinates
        var shotLeft = shot.x
        var shotRight = shot.x + shot.width
        var shotTop = shot.y
        var shotBottom = shot.y + shot.height

        // Check if any asteroid polygon point is inside shot bounds
        for (var i = 0; i < asteroid.asteroidPoints.length; i++) {
            var pointX = asteroid.x + asteroid.asteroidPoints[i].x
            var pointY = asteroid.y + asteroid.asteroidPoints[i].y
            if (pointX >= shotLeft && pointX <= shotRight &&
                pointY >= shotTop && pointY <= shotBottom) {
                return true
            }
        }

        // Check if shot corners are inside asteroid polygon (for edge cases)
        var corners = [
            {x: shotLeft, y: shotTop},           // Top-left
            {x: shotRight, y: shotTop},          // Top-right
            {x: shotRight, y: shotBottom},       // Bottom-right
            {x: shotLeft, y: shotBottom}         // Bottom-left
        ]
        for (var j = 0; j < corners.length; j++) {
            var localX = corners[j].x - asteroid.x
            var localY = corners[j].y - asteroid.y
            if (pointInPolygon(localX, localY, asteroid.asteroidPoints)) {
                return true
            }
        }

        return false
    }

    function handleShotAsteroidCollision(shot, asteroid) {
        var asteroidCenterX = asteroid.x + asteroid.width / 2
        var asteroidCenterY = asteroid.y + asteroid.height / 2
        var perimeterCenterX = root.width / 2
        var perimeterCenterY = root.height / 2
        var distance = Math.sqrt(
            Math.pow(asteroidCenterX - perimeterCenterX, 2) +
            Math.pow(asteroidCenterY - perimeterCenterY, 2)
        )
        var perimeterRadius = dimsFactor * 27.5

        var basePoints
        if (asteroid.asteroidSize === "small") basePoints = 100
        else if (asteroid.asteroidSize === "mid") basePoints = 50
        else if (asteroid.asteroidSize === "large") basePoints = 20
        var points = distance < perimeterRadius ? basePoints * 2 : basePoints
        score += points

        // Create explosion first (z: 0)
        var explosion = explosionParticleComponent.createObject(gameContent, {
            "x": asteroid.x + asteroid.width / 2 - (asteroid.size * 2.33 * (asteroid.asteroidSize === "large" ? 1.0 : asteroid.asteroidSize === "mid" ? 1.25 : 1.333) / 2),
            "y": asteroid.y + asteroid.height / 2 - (asteroid.size * 2.33 * (asteroid.asteroidSize === "large" ? 1.0 : asteroid.asteroidSize === "mid" ? 1.25 : 1.333) / 2),
            "asteroidSize": asteroid.size,
            "explosionColor": "default"
        })

        // Then create score particle (z: 6)
        var particle = scoreParticleComponent.createObject(gameContent, {
            "x": asteroidCenterX - dimsFactor * 4,
            "y": asteroidCenterY - dimsFactor * 4,
            "text": "+" + points,
            "color": distance < perimeterRadius ? "#00FFFF" : "#67AAF9"
        })

        if (distance < perimeterRadius) {
            scorePerimeter.border.color = "#FFFFFF"
            scorePerimeter.color = "#074588"
            perimeterFlashTimer.restart()
        }

        var newThreshold = Math.floor(score / 10000) * 10000
        if (newThreshold > lastShieldAward) {
            shield += 1
            lastShieldAward = newThreshold
        }

        asteroid.split()
    }

    function checkPlayerAsteroidCollision(playerHitbox, asteroid) {
        var activeHitbox = (shield > 0) ? shieldHitbox : playerHitbox
        var playerX = playerContainer.x + activeHitbox.x
        var playerY = playerContainer.y + activeHitbox.y
        var corners = [
            {x: playerX, y: playerY},
            {x: playerX + activeHitbox.width, y: playerY},
            {x: playerX + activeHitbox.width, y: playerY + activeHitbox.height},
            {x: playerX, y: playerY + activeHitbox.height}
        ]

        for (var i = 0; i < corners.length; i++) {
            var localX = corners[i].x - asteroid.x
            var localY = corners[i].y - asteroid.y
            if (pointInPolygon(localX, localY, asteroid.asteroidPoints)) {
                return true
            }
        }

        var playerLeft = playerX
        var playerRight = playerX + activeHitbox.width
        var playerTop = playerY
        var playerBottom = playerY + activeHitbox.height
        for (var j = 0; j < asteroid.asteroidPoints.length; j++) {
            var pointX = asteroid.x + asteroid.asteroidPoints[j].x
            var pointY = asteroid.y + asteroid.asteroidPoints[j].y
            if (pointX >= playerLeft && pointX <= playerRight &&
                pointY >= playerTop && pointY <= playerBottom) {
                return true
            }
        }

        return false
    }

    function handlePlayerAsteroidCollision(asteroid) {
        if (shield > 0) {
            shield -= 1
            asteroid.destroy()
            var index = activeAsteroids.indexOf(asteroid)
            if (index !== -1) {
                activeAsteroids.splice(index, 1)
            }
            var explosion = explosionParticleComponent.createObject(gameContent, {
                "x": asteroid.x + asteroid.width / 2 - (asteroid.size * 2.33 / 2),  // Center on asteroid
                "y": asteroid.y + asteroid.height / 2 - (asteroid.size * 2.33 / 2),
                "asteroidSize": asteroid.size,
                "explosionColor": "shield"
            })
            feedback.play()
        } else {
            gameOver = true
            asteroidSpawnTimer.stop()
            for (var i = 0; i < activeAsteroids.length; i++) {
                if (activeAsteroids[i]) activeAsteroids[i].destroy()
            }
            for (var j = 0; j < activeShots.length; j++) {
                if (activeShots[j]) activeShots[j].destroy()
            }
            activeAsteroids = []
            activeShots = []
            feedback.play()
        }
    }

    function checkCollision(asteroid1, asteroid2) {
        var dx = (asteroid1.x + asteroid1.width / 2) - (asteroid2.x + asteroid2.width / 2)
        var dy = (asteroid1.y + asteroid1.height / 2) - (asteroid2.y + asteroid2.height / 2)
        var distance = Math.sqrt(dx * dx + dy * dy)
        var minDistance = (asteroid1.size + asteroid2.size) / 2  // Simple radius-based collision
        return distance < minDistance
    }

    function handleAsteroidCollision(asteroid1, asteroid2) {
        // Calculate collision normal (direction from asteroid1 to asteroid2)
        var nx = (asteroid2.x + asteroid2.width / 2) - (asteroid1.x + asteroid1.width / 2)
        var ny = (asteroid2.y + asteroid2.height / 2) - (asteroid1.y + asteroid1.height / 2)
        var mag = Math.sqrt(nx * nx + ny * ny)
        if (mag === 0) return  // Avoid division by zero
        nx /= mag
        ny /= mag

        // Velocities (direction * speed)
        var v1x = asteroid1.directionX * asteroid1.speed
        var v1y = asteroid1.directionY * asteroid1.speed
        var v2x = asteroid2.directionX * asteroid2.speed
        var v2y = asteroid2.directionY * asteroid2.speed

        // Mass based on size (proxy)
        var mass1 = asteroid1.size * asteroid1.size  // Area as mass
        var mass2 = asteroid2.size * asteroid2.size
        var totalMass = mass1 + mass2

        // Momentum along normal
        var dot1 = v1x * nx + v1y * ny  // Velocity of asteroid1 along normal
        var dot2 = v2x * nx + v2y * ny  // Velocity of asteroid2 along normal

        // New velocities along normal, factoring in mass ratio
        var newDot1 = (dot1 * (mass1 - mass2) + 2 * mass2 * dot2) / totalMass
        var newDot2 = (dot2 * (mass2 - mass1) + 2 * mass1 * dot1) / totalMass

        // Update velocities, keeping speed constant
        var newV1x = v1x - dot1 * nx + newDot1 * nx
        var newV1y = v1y - dot1 * ny + newDot1 * ny
        var newV2x = v2x - dot2 * nx + newDot2 * nx
        var newV2y = v2y - dot2 * ny + newDot2 * ny

        // Normalize directions, preserve original speeds
        var mag1 = Math.sqrt(newV1x * newV1x + newV1y * newV1y)
        var mag2 = Math.sqrt(newV2x * newV2x + newV2y * newV2y)
        if (mag1 > 0) {
            asteroid1.directionX = newV1x / mag1
            asteroid1.directionY = newV1y / mag1
            // Speed remains asteroid1.speed (0.3, 0.4, or 0.6)
        }
        if (mag2 > 0) {
            asteroid2.directionX = newV2x / mag2
            asteroid2.directionY = newV2y / mag2
            // Speed remains asteroid2.speed (0.3, 0.4, or 0.6)
        }

        // Push asteroids apart to prevent sticking
        var overlap = (asteroid1.size + asteroid2.size) / 2 - mag
        if (overlap > 0) {
            var pushX = nx * overlap * 0.5
            var pushY = ny * overlap * 0.5
            asteroid1.x -= pushX * (mass2 / totalMass)  // Larger mass moves less
            asteroid1.y -= pushY * (mass2 / totalMass)
            asteroid2.x += pushX * (mass1 / totalMass)
            asteroid2.y += pushY * (mass1 / totalMass)
        }
    }

    function restartGame() {
        score = 0
        shield = 3
        level = 1
        gameOver = false
        paused = false
        calibrating = false
        calibrationTimer = 4
        lastFrameTime = 0
        playerRotation = 0
        initialAsteroidsToSpawn = 5
        asteroidsSpawned = 0
        afterBurnerActive = false
        afterBurnerTimeLeft = 0
        afterBurnerCooldown = 0
        playerContainer.x = centerX
        playerContainer.y = centerY
        for (var i = 0; i < activeShots.length; i++) {
            if (activeShots[i]) activeShots[i].destroy()
        }
        for (var j = 0; j < activeAsteroids.length; j++) {
            if (activeAsteroids[j]) activeAsteroids[j].destroy()
        }
        activeShots = []
        activeAsteroids = []
        asteroidSpawnTimer.restart()  // Restarts with triggeredOnStart
    }

    Component.onCompleted: {
        DisplayBlanking.preventBlanking = true
    }
}
