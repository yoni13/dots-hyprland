import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "add_reaction"
        title: Translation.tr("Custom Emoji")

        ContentSubsection {
            title: Translation.tr("Add New Custom Emoji")

            MaterialTextField {
                id: emojiNameInput
                Layout.fillWidth: true
                placeholderText: Translation.tr("Emoji name (e.g., my_custom_emoji)")
            }

            MaterialTextField {
                id: emojiKeywordsInput
                Layout.fillWidth: true
                placeholderText: Translation.tr("Keywords for search (e.g., custom special unique)")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialTextField {
                    id: emojiFilePathInput
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Select an image file...")
                    readOnly: true
                }

                RippleButton {
                    buttonText: Translation.tr("Browse")
                    Layout.preferredWidth: 100
                    onClicked: {
                        fileDialog.open()
                    }
                }
            }

            Text {
                id: addEmojiStatus
                visible: false
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RippleButton {
                Layout.fillWidth: true
                buttonText: Translation.tr("Add Custom Emoji")
                enabled: emojiNameInput.text.trim() !== "" && emojiFilePathInput.text.trim() !== ""
                onClicked: {
                    const result = Emojis.addCustomEmoji(
                        emojiNameInput.text.trim(),
                        emojiKeywordsInput.text.trim(),
                        emojiFilePathInput.text.trim()
                    )
                    
                    if (result.success) {
                        emojiNameInput.text = ""
                        emojiKeywordsInput.text = ""
                        emojiFilePathInput.text = ""
                        addEmojiStatus.text = Translation.tr("✓ Custom emoji added successfully!")
                        addEmojiStatus.color = "#4CAF50"
                        addEmojiStatus.visible = true
                        statusTimer.restart()
                    } else {
                        addEmojiStatus.text = "✗ " + result.error
                        addEmojiStatus.color = "#f44336"
                        addEmojiStatus.visible = true
                    }
                }
            }

            Timer {
                id: statusTimer
                interval: 3000
                onTriggered: {
                    addEmojiStatus.visible = false
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Manage Custom Emoji")

            ListView {
                id: customEmojiListView
                Layout.fillWidth: true
                implicitHeight: Math.min(300, contentHeight)
                clip: true
                spacing: 8
                model: Emojis.customEmojiList

                delegate: Rectangle {
                    required property int index
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    height: 60
                    radius: 8
                    color: Appearance.colors.colBackgroundSurfaceContainerHighest

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 12

                        Image {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            source: `file://${modelData.imagePath}`
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: modelData.name
                                font.weight: Font.Medium
                                font.pixelSize: 14
                                color: Appearance.colors.colTextPrimary
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.keywords
                                opacity: 0.7
                                font.pixelSize: 12
                                color: Appearance.colors.colTextPrimary
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        RippleButton {
                            buttonText: Translation.tr("Remove")
                            Layout.preferredHeight: 36
                            onClicked: {
                                Emojis.removeCustomEmoji(index)
                            }
                        }
                    }
                }
            }

            Text {
                visible: Emojis.customEmojiList.length === 0
                text: Translation.tr("No custom emoji added yet. Use the form above to add one.")
                opacity: 0.6
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                color: Appearance.colors.colTextPrimary
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: Translation.tr("Select Emoji Image")
        nameFilters: ["Image files (*.png *.jpg *.jpeg *.gif *.webp)"]
        onAccepted: {
            const path = fileDialog.selectedFile.toString()
            // Remove file:// prefix if present
            emojiFilePathInput.text = path.replace(/^file:\/\//, "")
        }
    }

    ContentSection {
        icon: "neurology"
        title: Translation.tr("AI")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("System prompt")
            text: Config.options.ai.systemPrompt
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Music Recognition")

        ConfigSpinBox {
            icon: "timer_off"
            text: Translation.tr("Total duration timeout (s)")
            value: Config.options.musicRecognition.timeout
            from: 10
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.musicRecognition.timeout = value;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (s)")
            value: Config.options.musicRecognition.interval
            from: 2
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.musicRecognition.interval = value;
            }
        }
    }

    ContentSection {
        icon: "cell_tower"
        title: Translation.tr("Networking")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("User agent (for services that require it)")
            text: Config.options.networking.userAgent
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.networking.userAgent = text;
            }
        }
    }

    ContentSection {
        icon: "memory"
        title: Translation.tr("Resources")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (ms)")
            value: Config.options.resources.updateInterval
            from: 100
            to: 10000
            stepSize: 100
            onValueChanged: {
                Config.options.resources.updateInterval = value;
            }
        }
        
    }

    ContentSection {
        icon: "file_open"
        title: Translation.tr("Save paths")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Video Recording Path")
            text: Config.options.screenRecord.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenRecord.savePath = text;
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Screenshot Path (leave empty to just copy)")
            text: Config.options.screenSnip.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenSnip.savePath = text;
            }
        }
    }

    ContentSection {
        icon: "search"
        title: Translation.tr("Search")

        ConfigSwitch {
            text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
            checked: Config.options.search.sloppy
            onCheckedChanged: {
                Config.options.search.sloppy = checked;
            }
            StyledToolTip {
                text: Translation.tr("Could be better if you make a ton of typos,\nbut results can be weird and might not work with acronyms\n(e.g. \"GIMP\" might not give you the paint program)")
            }
        }

        ContentSubsection {
            title: Translation.tr("Prefixes")
            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Action")
                    text: Config.options.search.prefix.action
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.action = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Clipboard")
                    text: Config.options.search.prefix.clipboard
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.clipboard = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Emojis")
                    text: Config.options.search.prefix.emojis
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.emojis = text;
                    }
                }
            }

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Math")
                    text: Config.options.search.prefix.math
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.math = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Shell command")
                    text: Config.options.search.prefix.shellCommand
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.shellCommand = text;
                    }
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Web search")
                    text: Config.options.search.prefix.webSearch
                    wrapMode: TextEdit.Wrap
                    onTextChanged: {
                        Config.options.search.prefix.webSearch = text;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Web search")
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Base URL")
                text: Config.options.search.engineBaseUrl
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.search.engineBaseUrl = text;
                }
            }
        }
    }

    ContentSection {
        icon: "weather_mix"
        title: Translation.tr("Weather")
        ConfigRow {
            ConfigSwitch {
                buttonIcon: "assistant_navigation"
                text: Translation.tr("Enable GPS based location")
                checked: Config.options.bar.weather.enableGPS
                onCheckedChanged: {
                    Config.options.bar.weather.enableGPS = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "thermometer"
                text: Translation.tr("Fahrenheit unit")
                checked: Config.options.bar.weather.useUSCS
                onCheckedChanged: {
                    Config.options.bar.weather.useUSCS = checked;
                }
                StyledToolTip {
                    text: Translation.tr("It may take a few seconds to update")
                }
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("City name")
            text: Config.options.bar.weather.city
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.bar.weather.city = text;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }
}
