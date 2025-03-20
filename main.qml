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
    property real lastFrameTime: 0

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
                calibrating = false
                feedback.play()
            }
        }
    }

    Timer {
        id: autoFireTimer
        interval: 500  // Fire every 500ms
        running: !gameOver && !calibrating && !paused
        repeat: true
        onTriggered: {
            var shot = autoFireShotComponent.createObject(gameArea, {
                "x": playerContainer.x + playerHitbox.x + playerHitbox.width / 2 - dimsFactor * 0.5,
                "y": playerContainer.y + playerHitbox.y
            })
            activeShots.push(shot)
        }
    }

    Component {
        id: autoFireShotComponent
        Rectangle {
            width: dimsFactor * 1
            height: dimsFactor * 5
            color: "#800080"
            z: 2
            visible: true
            property real speed: 5  // Speed of shots
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
        }

        Item {
            id: gameContent
            anchors.fill: parent

            Item {
                id: playerContainer
                x: root.width / 2 - player.width / 2 + dimsFactor * 5  // Shift right by half width
                y: root.height / 2 - player.height / 2 + dimsFactor * 5  // Shift down by half height
                z: 1
                visible: !calibrating

                Image {
                    id: player
                    width: dimsFactor * 10
                    height: dimsFactor * 10
                    source: "file:///usr/share/asteroid-launcher/watchfaces-img/asteroid-logo.svg"
                    anchors.centerIn: parent
                }

                Shape {
                    id: playerHitbox
                    width: dimsFactor * 14
                    height: dimsFactor * 14
                    anchors.centerIn: parent
                    visible: false

                    ShapePath {
                        strokeWidth: -1
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
                color: "#dddddd"
                font {
                    pixelSize: dimsFactor * 9
                    family: "Fyodor"
                }
                anchors {
                    top: root.top
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !gameOver && !calibrating
            }

            Text {
                id: shieldText
                text: "Shields: " + shield
                color: "#FFFFFF"
                font {
                    pixelSize: dimsFactor * 8
                    family: "Fyodor"
                }
                anchors {
                    bottom: scoreText.top
                    horizontalCenter: parent.horizontalCenter
                }
                z: 4
                visible: !gameOver && !calibrating
            }

            Text {
                id: scoreText
                text: "Score: " + score
                color: "#FFFFFF"
                font {
                    pixelSize: dimsFactor * 8
                    family: "Fyodor"
                }
                anchors {
                    bottom: parent.bottom
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
                    text: "v0.9\nAsteroids"
                    color: "#dddddd"
                    font {
                        family: "Fyodor"
                        pixelSize: dimsFactor * 15
                    }
                    anchors {
                        bottom: calibrationText.top
                        horizontalCenter: parent.horizontalCenter
                    }
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    id: calibrationText
                    anchors.centerIn: parent
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
                    family: "Fyodor"
                }
                anchors.centerIn: parent
                opacity: 0
                z: 2  // Above player (z: 1)
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

                Row {
                    anchors.fill: parent
                    spacing: 0
                    Repeater {
                        model: 10
                        Rectangle {
                            width: fpsGraph.width / 10
                            height: {
                                var fps = index < gameTimer.fpsHistory.length ? gameTimer.fpsHistory[index] : 0
                                return Math.min(dimsFactor * 10, Math.max(0, (fps / 60) * dimsFactor * 10))
                            }
                            color: {
                                var fps = index < gameTimer.fpsHistory.length ? gameTimer.fpsHistory[index] : 0
                                if (fps > 60) return "green"
                                else if (fps >= 50) return "orange"
                                else return "red"
                            }
                        }
                    }
                }
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
            id: gameOverScreen
            anchors.centerIn: parent
            z: 5
            visible: gameOver
            opacity: 0
            Behavior on opacity {
                NumberAnimation { duration: 250 }
            }
            onVisibleChanged: {
                if (visible) {
                    opacity = 1
                } else {
                    opacity = 0
                }
            }

            Column {
                spacing: Math.round(dimsFactor * 6 * 1.2)
                anchors.centerIn: parent

                Text {
                    id: gameOverText
                    text: "Game Over!"
                    color: "red"
                    font {
                        pixelSize: Math.round(dimsFactor * 8 * 1.2)
                        bold: true
                    }
                    horizontalAlignment: Text.AlignHCenter
                }

                Column {
                    spacing: Math.round(dimsFactor * 1 * 1.2)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Row {
                        spacing: Math.round(dimsFactor * 2 * 1.2)
                        Text { text: "Score"; color: "#dddddd"; font.pixelSize: Math.round(dimsFactor * 4 * 1.2); width: Math.round(dimsFactor * 22 * 1.2); horizontalAlignment: Text.AlignHCenter }
                        Text { text: score; color: "white"; font.pixelSize: Math.round(dimsFactor * 5 * 1.2); font.bold: true; width: Math.round(dimsFactor * 11 * 1.2); horizontalAlignment: Text.AlignHCenter }
                    }
                    Row {
                        spacing: Math.round(dimsFactor * 2 * 1.2)
                        Text { text: "Level"; color: "#dddddd"; font.pixelSize: Math.round(dimsFactor * 4 * 1.2); width: Math.round(dimsFactor * 22 * 1.2); horizontalAlignment: Text.AlignHCenter }
                        Text { text: level; color: "white"; font.pixelSize: Math.round(dimsFactor * 5 * 1.2); font.bold: true; width: Math.round(dimsFactor * 11 * 1.2); horizontalAlignment: Text.AlignHCenter }
                    }
                    Row {
                        spacing: Math.round(dimsFactor * 2 * 1.2)
                        Text { text: "High Score"; color: "#dddddd"; font.pixelSize: Math.round(dimsFactor * 4 * 1.2); width: Math.round(dimsFactor * 22 * 1.2); horizontalAlignment: Text.AlignHCenter }
                        Text { text: highScore.value; color: "white"; font.pixelSize: Math.round(dimsFactor * 5 * 1.2); font.bold: true; width: Math.round(dimsFactor * 11 * 1.2); horizontalAlignment: Text.AlignHCenter }
                    }
                    Row {
                        spacing: Math.round(dimsFactor * 2 * 1.2)
                        Text { text: "Max Level"; color: "#dddddd"; font.pixelSize: Math.round(dimsFactor * 4 * 1.2); width: Math.round(dimsFactor * 22 * 1.2); horizontalAlignment: Text.AlignHCenter }
                        Text { text: highLevel.value; color: "white"; font.pixelSize: Math.round(dimsFactor * 5 * 1.2); font.bold: true; width: Math.round(dimsFactor * 11 * 1.2); horizontalAlignment: Text.AlignHCenter }
                    }
                }

                Rectangle {
                    id: tryAgainButton
                    width: Math.round(dimsFactor * 42 * 1.2)
                    height: Math.round(dimsFactor * 14 * 1.2)
                    color: "green"
                    border.color: "white"
                    border.width: Math.round(dimsFactor * 1 * 1.2)
                    radius: Math.round(dimsFactor * 3 * 1.2)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        text: "Try Again"
                        color: "white"
                        font {
                            pixelSize: Math.round(dimsFactor * 6 * 1.2)
                            bold: true
                        }
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: gameOver
                        onClicked: {
                            restartGame()
                            gameOver = false
                        }
                    }
                }
            }
        }
    }

    function updateGame(deltaTime) {
        // Update shots
        for (var i = activeShots.length - 1; i >= 0; i--) {
            var shot = activeShots[i]
            if (shot) {
                shot.y -= shot.speed * deltaTime * 60
                if (shot.y <= -shot.height) {
                    shot.destroy()
                    activeShots.splice(i, 1)
                }
            }
        }
    }

    function restartGame() {
        score = 0
        shield = 2
        level = 1
        gameOver = false
        paused = false
        calibrating = true
        calibrationTimer = 4
        lastFrameTime = 0
        for (var i = 0; i < activeShots.length; i++) {
            if (activeShots[i]) {
                activeShots[i].destroy()
            }
        }
        activeShots = []
    }

    Component.onCompleted: {
        DisplayBlanking.preventBlanking = true
    }
}
