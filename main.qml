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
    property int shield: 2
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
        interval: 200
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
        interval: 4000  // 4 seconds delay between spawns
        running: !gameOver && !calibrating && !paused && asteroidsSpawned < initialAsteroidsToSpawn
        repeat: true
        onTriggered: {
            spawnLargeAsteroid()
            asteroidsSpawned++
            if (asteroidsSpawned >= initialAsteroidsToSpawn) {
                stop()  // Stop spawning once all initial asteroids are out
            }
        }
    }

    Component {
        id: autoFireShotComponent
        Rectangle {
            width: dimsFactor * 1.5
            height: dimsFactor * 3
            color: "#800080"
            z: 2
            visible: true
            property real speed: 5
            property real directionX: 0
            property real directionY: -1
            rotation: playerRotation
        }
    }

    Component {
        id: asteroidComponent
        Shape {
            id: asteroid
            property real size: Dims.l(18)  // Default large size (was 15, +20% ≈ 18)
            property real speed: {
                if (asteroidSize === "large") return (2 + level * 0.5) * 0.12
                if (asteroidSize === "mid") return (2 + level * 0.5) * 0.22
                if (asteroidSize === "small") return (2 + level * 0.5) * 0.32
                return 2 + level * 0.5
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
                duration: Math.abs(360 / rotationSpeed) * 1000  // Time for one full rotation in ms
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
                    spawnSplitAsteroids("mid", Dims.l(12), 2, x, y, directionX, directionY);  // Mid size was 10, +20% ≈ 12
                } else if (asteroidSize === "mid" && activeAsteroids.filter(a => a.asteroidSize === "small").length < 20) {
                    spawnSplitAsteroids("small", Dims.l(6), 2, x, y, directionX, directionY);  // Small size was 5, +20% ≈ 6
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

            Item {
                id: playerContainer
                x: root.width / 2 - player.width / 2 + dimsFactor * 5
                y: root.height / 2 - player.height / 2 + dimsFactor * 5
                z: 1
                visible: !calibrating

                Rectangle {
                    id: afterBurnerEffect
                    width: dimsFactor * 5
                    height: dimsFactor * 10
                    color: "#ff8000"  // Orange flame-like color
                    anchors.horizontalCenter: player.horizontalCenter
                    anchors.top: player.bottom
                    opacity: afterBurnerActive ? 0.8 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }

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
            }

            Text {
                id: levelNumber
                text: level
                color: "#dddddd"
                font {
                    pixelSize: dimsFactor * 10
                    family: "Teko"
                    styleName: "Bold"
                }
                anchors {
                    top: root.top
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !gameOver && !calibrating
            }

            Text {
                id: scoreText
                text: score
                color: "#FFFFFF"
                font {
                    pixelSize: dimsFactor * 14
                    family: "Teko"
                    styleName: "Light"
                }
                anchors {
                    bottom: shieldText.top
                    bottomMargin: -dimsFactor * 6
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !gameOver && !calibrating
            }

            Text {
                id: shieldText
                text: shield
                color: "#FFFFFF"
                font {
                    pixelSize: dimsFactor * 10
                    family: "Teko"
                    styleName: "Bold"
                }
                anchors {
                    bottom: parent.bottom
                    bottomMargin: -dimsFactor * 4
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !gameOver && !calibrating
            }

            Item {
                id: calibrationContainer
                anchors.fill: parent
                visible: calibrating

                Text {
                    text: "v0.9\nAsteroid Blaster"
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
                        bottomMargin: Dims.l(10)
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

            Rectangle {
                anchors.fill: parent
                color: "#80000000"
            }

            Text {
                id: gameOverText
                text: "Game Over"
                color: "white"
                font {
                    pixelSize: dimsFactor * 18
                    family: "Teko"
                    styleName: "Medium"
                }
                anchors {
                    bottom: scoreOverText.top
                    bottomMargin: -dimsFactor * 6
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
                    pixelSize: dimsFactor * 9
                    family: "Teko"
                }
                anchors {
                    bottom: parent.verticalCenter
                    bottomMargin: dimsFactor * 2
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
                    pixelSize: dimsFactor * 9
                    family: "Teko"
                }
                anchors {
                    top: parent.verticalCenter
                    topMargin: dimsFactor * 2
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
                        styleName: "Bold"
                    }
                    anchors.centerIn: parent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (score > highScore.value) {
                            highScore.value = score
                        }
                        if (level > highLevel.value) {
                            highLevel.value = level
                        }
                        restartGame()
                    }
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

                    // Player-asteroid collision check
                    if (checkPlayerAsteroidCollision(playerHitbox, asteroid)) {
                        handlePlayerAsteroidCollision(asteroid)
                    }
                }
            }

            // Afterburner logic
            if (afterBurnerActive && afterBurnerTimeLeft > 0) {
                afterBurnerTimeLeft -= deltaTime
                var rad = playerRotation * Math.PI / 180
                var boostSpeed = dimsFactor * 100  // Speed of boost (pixels per second)
                var dx = Math.sin(rad) * boostSpeed * deltaTime
                var dy = -Math.cos(rad) * boostSpeed * deltaTime
                var newX = playerContainer.x + dx
                var newY = playerContainer.y + dy

                // Limit distance from center
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
                }
            } else if (!afterBurnerActive) {
                // Drift back to center
                var returnSpeed = dimsFactor * 20  // Slower return speed
                var dx = centerX - playerContainer.x
                var dy = centerY - playerContainer.y
                var distance = Math.sqrt(dx * dx + dy * dy)
                if (distance > dimsFactor * 5) {  // Small threshold to avoid jitter
                    var moveX = (dx / distance) * returnSpeed * deltaTime
                    var moveY = (dy / distance) * returnSpeed * deltaTime
                    playerContainer.x += moveX
                    playerContainer.y += moveY
                } else {
                    playerContainer.x = centerX
                    playerContainer.y = centerY
                }
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
        if (activeAsteroids.filter(a => a.asteroidSize === "large").length >= 5) return
        var size = Dims.l(18)  // Was 15, +20% ≈ 18
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
            initialAsteroidsToSpawn = 4 + level  // 5 at level 1, 6 at level 2, etc.
            asteroidsSpawned = 0
            asteroidSpawnTimer.restart()  // Start spawning for the next level
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
        // Translate shot center to asteroid-local coordinates
        var shotCenterX = shot.x + shot.width / 2 - asteroid.x
        var shotCenterY = shot.y + shot.height / 2 - asteroid.y

        // Check if shot center is inside asteroid's polygon
        return pointInPolygon(shotCenterX, shotCenterY, asteroid.asteroidPoints)
    }

    function handleShotAsteroidCollision(shot, asteroid) {
        // Award points based on asteroid size (original Asteroids scoring)
        if (asteroid.asteroidSize === "small") {
            score += 20
        } else if (asteroid.asteroidSize === "mid") {
            score += 50
        } else if (asteroid.asteroidSize === "large") {
            score += 100
        }

        // Check for shield bonus every 10,000 points
        var newThreshold = Math.floor(score / 10000) * 10000
        if (newThreshold > lastShieldAward) {
            shield += 1
            lastShieldAward = newThreshold
        }

        // Split or destroy asteroid
        asteroid.split()
    }

    function checkPlayerAsteroidCollision(playerHitbox, asteroid) {
        // Player hitbox corners in global coordinates
        var playerX = playerContainer.x + playerHitbox.x
        var playerY = playerContainer.y + playerHitbox.y
        var corners = [
            {x: playerX, y: playerY},                          // Top-left
            {x: playerX + playerHitbox.width, y: playerY},     // Top-right
            {x: playerX + playerHitbox.width, y: playerY + playerHitbox.height}, // Bottom-right
            {x: playerX, y: playerY + playerHitbox.height}     // Bottom-left
        ]

        // Translate corners to asteroid-local coordinates and check each
        for (var i = 0; i < corners.length; i++) {
            var localX = corners[i].x - asteroid.x
            var localY = corners[i].y - asteroid.y
            if (pointInPolygon(localX, localY, asteroid.asteroidPoints)) {
                return true
            }
        }

        // Also check if asteroid points are inside player hitbox (for edge cases)
        var playerLeft = playerX
        var playerRight = playerX + playerHitbox.width
        var playerTop = playerY
        var playerBottom = playerY + playerHitbox.height
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
        shield--
        asteroid.split()  // Asteroid splits or is destroyed upon hitting player
        feedback.play()  // Play feedback sound for impact
        if (shield <= 0) {
            gameOver = true
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

        // Elastic collision for equal mass billiard balls (no gravity)
        var dot1 = v1x * nx + v1y * ny  // Velocity of asteroid1 along normal
        var dot2 = v2x * nx + v2y * ny  // Velocity of asteroid2 along normal

        // New velocities after collision (swap normal components)
        var newV1x = v1x - dot1 * nx + dot2 * nx
        var newV1y = v1y - dot1 * ny + dot2 * ny
        var newV2x = v2x - dot2 * nx + dot1 * nx
        var newV2y = v2y - dot2 * ny + dot1 * ny

        // Normalize and update directions
        var mag1 = Math.sqrt(newV1x * newV1x + newV1y * newV1y)
        var mag2 = Math.sqrt(newV2x * newV2x + newV2y * newV2y)
        if (mag1 > 0) {
            asteroid1.directionX = newV1x / mag1
            asteroid1.directionY = newV1y / mag1
        }
        if (mag2 > 0) {
            asteroid2.directionX = newV2x / mag2
            asteroid2.directionY = newV2y / mag2
        }

        // Push asteroids apart to prevent sticking
        var overlap = (asteroid1.size + asteroid2.size) / 2 - mag
        if (overlap > 0) {
            var pushX = nx * overlap * 0.5
            var pushY = ny * overlap * 0.5
            asteroid1.x -= pushX
            asteroid1.y -= pushY
            asteroid2.x += pushX
            asteroid2.y += pushY
        }
    }

    function restartGame() {
        score = 0
        shield = 2
        level = 1
        gameOver = false
        paused = false
        calibrating = false
        calibrationTimer = 4
        lastFrameTime = 0
        playerRotation = 0
        initialAsteroidsToSpawn = 5
        asteroidsSpawned = 0
        afterBurnerActive = false  // Reset afterburner state
        afterBurnerTimeLeft = 0
        afterBurnerCooldown = 0
        playerContainer.x = centerX  // Reset position
        playerContainer.y = centerY
        for (var i = 0; i < activeShots.length; i++) {
            if (activeShots[i]) activeShots[i].destroy()
        }
        for (var j = 0; j < activeAsteroids.length; j++) {
            if (activeAsteroids[j]) activeAsteroids[j].destroy()
        }
        activeShots = []
        activeAsteroids = []
        asteroidSpawnTimer.restart()
    }

    Component.onCompleted: {
        DisplayBlanking.preventBlanking = true
    }
}
