pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Emojis.
 */
Singleton {
    id: root
    property string emojiScriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.sh`
	property string lineBeforeData: "### DATA ###"
    property string customEmojiDir: FileUtils.trimFileProtocol(`${Directories.cache}/media/custom-emoji`)
    property string customEmojiConfigPath: FileUtils.trimFileProtocol(`${Directories.shellConfig}/custom-emoji.json`)
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.3
    property list<var> list
    property list<var> customEmojiList: []
    readonly property var preparedEntries: list.map(a => ({
        name: Fuzzy.prepare(`${a}`),
        entry: a,
        isCustom: false,
        imagePath: undefined
    })).concat(customEmojiList.map(a => ({
        name: Fuzzy.prepare(`${a.name} ${a.keywords}`),
        entry: `${a.name} ${a.keywords}`,
        isCustom: true,
        imagePath: a.imagePath
    })))
    function fuzzyQuery(search: string): var {
        if (root.sloppySearch) {
            const results = preparedEntries.slice(0, 100).map(obj => ({
                entry: obj.entry,
                isCustom: obj.isCustom,
                imagePath: obj.imagePath,
                score: Levendist.computeTextMatchScore(obj.entry.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => ({
                    entry: item.entry,
                    isCustom: item.isCustom,
                    imagePath: item.imagePath
                }))
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return {
                entry: r.obj.entry,
                isCustom: r.obj.isCustom,
                imagePath: r.obj.imagePath
            }
        });
    }

    function load() {
        emojiFileView.reload()
    }

    function updateEmojis(fileContent) {
        const lines = fileContent.split("\n")
        const dataIndex = lines.indexOf(root.lineBeforeData)
        if (dataIndex === -1) {
            console.warn("No data section found in emoji script file.")
            return
        }
        const emojis = lines.slice(dataIndex + 1).filter(line => line.trim() !== "")
        root.list = emojis.map(line => line.trim())
    }

    function loadCustomEmojis() {
        customEmojiFileView.reload()
    }

    function addCustomEmoji(name, keywords, imagePath) {
        // Validate file type
        const validExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp']
        const hasValidExt = validExtensions.some(ext => imagePath.toLowerCase().endsWith(ext))
        if (!hasValidExt) {
            return { success: false, error: "Invalid file type. Supported: PNG, JPG, GIF, WEBP" }
        }

        // Check if file exists and get its size
        const statResult = Quickshell.execWait(["stat", "-c", "%s", imagePath])
        if (statResult.exitCode !== 0) {
            return { success: false, error: "File not found or cannot be accessed" }
        }
        
        const fileSize = parseInt(statResult.stdout.trim())
        const maxFileSize = 10 * 1024 * 1024 // 10 MB
        if (fileSize > maxFileSize) {
            return { success: false, error: "File too large. Maximum size is 10 MB" }
        }

        // Generate unique filename
        const timestamp = Date.now()
        const originalName = imagePath.split('/').pop()
        const extension = originalName.substring(originalName.lastIndexOf('.'))
        const newFileName = `custom_emoji_${timestamp}${extension}`
        const destPath = `${root.customEmojiDir}/${newFileName}`

        // Copy file to custom emoji directory
        const copyResult = Quickshell.execWait(["cp", imagePath, destPath])
        if (copyResult.exitCode !== 0) {
            return { success: false, error: "Failed to copy emoji file" }
        }

        // Add to custom emoji list
        const newEmoji = {
            name: name,
            keywords: keywords,
            imagePath: destPath,
            timestamp: timestamp
        }

        let customList = [...root.customEmojiList]
        customList.push(newEmoji)
        root.customEmojiList = customList

        // Save to config file
        saveCustomEmojis()

        return { success: true }
    }

    function removeCustomEmoji(index) {
        if (index < 0 || index >= root.customEmojiList.length) {
            return { success: false, error: "Invalid emoji index" }
        }

        const emoji = root.customEmojiList[index]
        
        // Remove the image file
        Quickshell.execDetached(["rm", "-f", emoji.imagePath])

        // Remove from list
        let customList = [...root.customEmojiList]
        customList.splice(index, 1)
        root.customEmojiList = customList

        // Save to config file
        saveCustomEmojis()

        return { success: true }
    }

    function saveCustomEmojis() {
        const data = JSON.stringify(root.customEmojiList, null, 2)
        customEmojiFileView.setText(data)
    }

    FileView { 
        id: emojiFileView
        path: Qt.resolvedUrl(root.emojiScriptPath)
        onLoadedChanged: {
            const fileContent = emojiFileView.text()
            root.updateEmojis(fileContent)
        }
    }

    FileView {
        id: customEmojiFileView
        path: root.customEmojiConfigPath
        onLoadedChanged: {
            try {
                const content = customEmojiFileView.text()
                if (content && content.trim() !== "") {
                    root.customEmojiList = JSON.parse(content)
                }
            } catch (e) {
                console.warn("Failed to load custom emoji:", e)
                root.customEmojiList = []
            }
        }
        onLoadFailed: error => {
            console.log("Custom emoji config not found, will create on first add")
            root.customEmojiList = []
        }
    }

    Component.onCompleted: {
        // Create custom emoji directory if it doesn't exist
        Quickshell.execDetached(["mkdir", "-p", root.customEmojiDir])
    }
}
