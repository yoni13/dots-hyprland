import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    forceWidth: true
    property string googleCredentialsImportPath: Config.options.googleWorkspace.credentialsPath

    Connections {
        target: GoogleWorkspace

        function onPendingCredentialDeletionPathChanged() {
            if (GoogleWorkspace.pendingCredentialDeletionPath)
                root.googleCredentialsImportPath = "";
        }
    }

    ContentSection {
        icon: "calendar_month"
        title: Translation.tr("Google Tasks & Calendar")

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Enable Google integration")
            checked: Config.options.googleWorkspace.enable
            onCheckedChanged: {
                Config.options.googleWorkspace.enable = checked;
                if (checked && GoogleWorkspace.connected)
                    GoogleWorkspace.refresh();

            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Desktop OAuth client JSON path")
            text: root.googleCredentialsImportPath
            wrapMode: TextEdit.Wrap
            onTextChanged: root.googleCredentialsImportPath = text
        }

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Sync interval (minutes)")
            value: Config.options.googleWorkspace.refreshInterval
            from: 5
            to: 120
            stepSize: 5
            onValueChanged: Config.options.googleWorkspace.refreshInterval = value
        }

        ConfigRow {
            RippleButtonWithIcon {
                materialIcon: "key"
                mainText: GoogleWorkspace.credentialsReady ? Translation.tr("Replace credentials") : Translation.tr("Import credentials")
                enabled: !GoogleWorkspace.busy && root.googleCredentialsImportPath.trim().length > 0
                onClicked: GoogleWorkspace.importCredentials(root.googleCredentialsImportPath)
            }

            RippleButtonWithIcon {
                materialIcon: GoogleWorkspace.connected ? "account_circle" : "login"
                mainText: GoogleWorkspace.connected ? Translation.tr("Reconnect") : Translation.tr("Connect Google")
                enabled: !GoogleWorkspace.busy && GoogleWorkspace.credentialsReady
                onClicked: GoogleWorkspace.connectAccount()
            }

            RippleButtonWithIcon {
                materialIcon: "sync"
                mainText: Translation.tr("Sync now")
                enabled: GoogleWorkspace.connected && !GoogleWorkspace.busy
                onClicked: GoogleWorkspace.refresh()
            }

            RippleButtonWithIcon {
                materialIcon: "logout"
                mainText: Translation.tr("Disconnect")
                enabled: GoogleWorkspace.connected && !GoogleWorkspace.busy
                onClicked: GoogleWorkspace.disconnectAccount()
            }

            RippleButtonWithIcon {
                materialIcon: "open_in_new"
                mainText: Translation.tr("Setup guide")
                onClicked: Qt.openUrlExternally("https://developers.google.com/workspace/guides/create-credentials#desktop-app")
            }

        }

        ContentSubsection {
            visible: GoogleWorkspace.pendingCredentialDeletionPath.length > 0
            title: Translation.tr("Delete the original credential file?")

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The OAuth credentials are now in your OS keyring. The original file is no longer needed:\n%1").arg(GoogleWorkspace.pendingCredentialDeletionPath)
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
            }

            ConfigRow {
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: Translation.tr("Delete original file")
                    enabled: !GoogleWorkspace.busy
                    onClicked: GoogleWorkspace.deleteImportedCredentialsFile()
                }
                RippleButtonWithIcon {
                    materialIcon: "keep"
                    mainText: Translation.tr("Keep file")
                    enabled: !GoogleWorkspace.busy
                    onClicked: GoogleWorkspace.keepImportedCredentialsFile()
                }
            }
        }

        StyledText {
            visible: GoogleWorkspace.credentialNotice.length > 0 && GoogleWorkspace.pendingCredentialDeletionPath.length === 0
            Layout.fillWidth: true
            text: GoogleWorkspace.credentialNotice
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText {
            Layout.fillWidth: true
            text: GoogleWorkspace.statusText
            color: GoogleWorkspace.errorMessage ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Requires a Desktop OAuth client with the Google Tasks and Calendar APIs enabled. OAuth credentials and tokens are stored in your OS keyring.")
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
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

    // There's no update indicator in ii for now so we shouldn't show this yet
    // ContentSection {
    //     icon: "deployed_code_update"
    //     title: Translation.tr("System updates (Arch only)")

    //     ConfigSwitch {
    //         text: Translation.tr("Enable update checks")
    //         checked: Config.options.updates.enableCheck
    //         onCheckedChanged: {
    //             Config.options.updates.enableCheck = checked;
    //         }
    //     }

    //     ConfigSpinBox {
    //         icon: "av_timer"
    //         text: Translation.tr("Check interval (mins)")
    //         value: Config.options.updates.checkInterval
    //         from: 60
    //         to: 1440
    //         stepSize: 60
    //         onValueChanged: {
    //             Config.options.updates.checkInterval = value;
    //         }
    //     }
    // }

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
