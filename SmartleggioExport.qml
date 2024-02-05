/*
 * Copyright © 2024 Dmitri Ovodok
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 2 of the License, or (at your option) any later
 * version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.

 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <https://www.gnu.org/licenses/>.
 */
import QtQuick 2.9
import QtQuick.Controls 1.4
import QtQuick.Dialogs 1.2
import QtQuick.Layouts 1.3
import Qt.labs.settings 1.0
import MuseScore 3.0
import FileIO 3.0

MuseScore {
    id: plugin
    menuPath: "Plugins.Smartleggio Export"
    version: "0.9.0"
    description: "Export the current score to Smartleggio format"
    requiresScore: true

    readonly property string name: "Smartleggio Export"
    readonly property string internalName: "SmartleggioExport"
    readonly property string exportedFileSuffix: ".smlgz"

    Settings {
        id: pluginSettings
        category: "plugins/smartleggio/export"

        property string selectedLayoutMode: ""
        property string selectedAspectRatio: ""
        property string customAspectRatioX: ""
        property string customAspectRatioY: ""
        property string selectedLayoutBreakMode: ""
    }

    FileIO {
        id: fileIO
        onError: {
            throw new Error("File operation error: " + msg);
        }
    }

    QProcess {
        id: qprocess

        function isWindows() {
            var os = Qt.platform.os;
            return os == "windows" || os == "winrt";
        }

        function checkFileExists(path) {
            var oldPath = fileIO.source;
            fileIO.source = path;
            var exists = fileIO.exists();
            fileIO.source = oldPath;
            return exists;
        }

        function executeCommandTemplate(cmd, args) {
            for (var key in args) {
                cmd = cmd.replace(new RegExp("\\{" + key + "\\}", "g"), args[key]);
            }

            console.log("Execute:", cmd);
            qprocess.start(cmd);
            var cmdOk = qprocess.waitForFinished();
            // TODO: how to check the exit code? waitForFinished doesn't seem to do it.

            if (!cmdOk) {
                throw new Error("Failed to execute external process:\n" + cmd + "\n" + readAllStandardOutput().toString());
            }
        }

        function makeGzipFile(srcPath, dstPath) {
            var cmd;

            if (isWindows()) {
                srcPath = srcPath.replace(/\//g, "\\");
                dstPath = dstPath.replace(/\//g, "\\");

                cmd = 'powershell -Command "$fIn = New-Object System.IO.FileStream("""{srcPath}""", [System.IO.FileMode]::Open); $fOut = New-Object System.IO.FileStream("""{dstPath}""", [System.IO.FileMode]::Create); $gzStream = New-Object System.IO.Compression.GZipStream($fOut, [System.IO.Compression.CompressionMode]::Compress); $buffer = New-Object byte[](4096); do { $readCount = $fIn.Read($buffer, 0, 4096); $gzStream.Write($buffer, 0, $readCount); } while($readCount -ne 0); $fIn.Close(); $fIn.Dispose(); $gzStream.Close(); $gzStream.Dispose(); $fOut.Close(); $fOut.Dispose();"'
            } else {
                srcPath = srcPath.replace(/'/g, "'\\''");
                dstPath = dstPath.replace(/'/g, "'\\''");
                cmd = 'bash -c "gzip -c \'{srcPath}\' > \'{dstPath}\'"'
            }

            executeCommandTemplate(cmd, {"srcPath": srcPath, "dstPath": dstPath});

            if (!checkFileExists(dstPath)) {
                throw new Error("Failed to compress file");
            }
        }

        function moveFile(srcPath, dstPath) {
            var cmd;

            if (isWindows()) {
                srcPath = srcPath.replace(/^\//, "").replace(/\//g, "\\");
                dstPath = dstPath.replace(/^\//, "").replace(/\//g, "\\");
                cmd = 'cmd /c MOVE /Y "{srcPath}" "{dstPath}"'
            } else {
                srcPath = srcPath.replace(/'/g, "'\\''");
                dstPath = dstPath.replace(/'/g, "'\\''");
                cmd = 'bash -c "mv -f \'{srcPath}\' \'{dstPath}\'"'
            }

            executeCommandTemplate(cmd, {"srcPath": srcPath, "dstPath": dstPath});

            // Move command removes the source file if and only if the operation
            // is successful, so we check existense of the source file.
            if (checkFileExists(srcPath)) {
                throw new Error("Failed to write a file at the chosen location.\nPlease choose a different location.");
            }
        }
    }

    FileDialog {
        id: exportFileDialog
        title: plugin.name
        modality: Qt.ApplicationModal
        selectExisting: false
        selectFolder: false
        selectMultiple: false
        nameFilters: ["Exported scores (*" + exportedFileSuffix + ")"]

        property var exportSettings: null
        property var score: null

        property var platformDialog: null

        onAccepted: onDialogAccepted(fileUrl)

        function onDialogAccepted(fileUrl) {
            var filePath = fileUrl.toString().replace(/file:\/\//, "");
            if (!filePath.endsWith(exportedFileSuffix)) {
                if (exportSettings.layoutMode != "preserve") {
                    var aspectRatio = exportSettings.aspectRatio;
                    filePath += "." + aspectRatio.y + "x" + aspectRatio.x;
                }
                filePath += exportedFileSuffix;
            }
            plugin.exportScore(score, filePath, exportSettings);
        }

        function openSaveFileDialog() {
            if (Qt.platform.os == "osx") {
                // A usual FileDialog doesn't show from QML on MacOS, use a
                // dialog with the DontUseNativeDialog flag to work around this.
                // Qt.labs.platform is unavailable in the AppImage for Linux on
                // MuseScore 3.6.2, so it has to be created dynamically.
                platformDialog = Qt.createQmlObject('import Qt.labs.platform 1.0 as Platform; Platform.FileDialog { fileMode: Platform.FileDialog.SaveFile; onAccepted: exportFileDialog.onDialogAccepted(file); }', plugin, "dynamicPlatformFileDialog");
                platformDialog.title = title;
                platformDialog.defaultSuffix = exportedFileSuffix;
                platformDialog.nameFilters = nameFilters;
                platformDialog.options = (16) // DontUseNativeDialog. On Qt 6 the value is 8 and exposed to QML in a usual (non-Labs) FileDialog.
                platformDialog.open()
            } else {
                open();
            }
        }
    }

    Dialog {
        id: exportSettingsDialog
        title: plugin.name
        modality: Qt.ApplicationModal
        standardButtons: StandardButton.Save | StandardButton.Cancel

        Column {
            spacing: 4

            RowLayout {
                ExclusiveGroup { id: layoutModeGroup }
                RadioButton {
                    id: layoutModeRadioButtonAdapt
                    text: "Adapt to aspect ratio"
                    checked: true
                    exclusiveGroup: layoutModeGroup
                    property string settingsId: "adapt"
                }
                RadioButton {
                    id: layoutModeRadioButtonPreserve
                    text: "Preserve original layout"
                    exclusiveGroup: layoutModeGroup
                    property string settingsId: "preserve"
                }
                Layout.fillWidth: true
            }

            Label {
                width: parent.width
                text: layoutModeRadioButtonAdapt.checked
                    ? "The score will automatically be adapted to the selected screen aspect ratio."
                    : "The score will be exported with its current layout without any automatic changes."
                wrapMode: Text.Wrap
            }

            GridLayout {
                anchors.left: parent.left
                anchors.right: parent.right

                visible: layoutModeRadioButtonAdapt.checked
                columns: 2
                columnSpacing: 8
                rowSpacing: 4


                Label {
                    height: aspectRatioComboBox.height
                    text: "Aspect ratio:"
                    verticalAlignment: Text.AlignVCenter
                }
                ComboBox {
                    id: aspectRatioComboBox
                    model: ListModel {
                        id: aspectRatioOptionsModel
                        ListElement { settingsId: "4x3"; text: "4:3 (iPad)"; y: 4; x: 3 }
                        ListElement { settingsId: "16x10"; text: "16:10 (Most Android tablets)"; y: 16; x: 10 }
                        ListElement { settingsId: "16x9"; text: "16:9 (Most desktop screens, some smartphones)"; y: 16; x: 9 }
                        ListElement { settingsId: "2x1"; text: "2:1 (Most smartphones)"; y: 2; x: 1 }
                        ListElement { settingsId: "custom"; text: "Custom"; y: 0; x: 0 }
                    }
                    Layout.fillWidth: true
                }

                Row {
                    visible: aspectRatioOptionsModel.get(aspectRatioComboBox.currentIndex).settingsId === "custom"
                    spacing: 4
                    Label {
                        height: customAspectRatioYTextField.height
                        text: "Y:"
                        verticalAlignment: Text.AlignVCenter
                    }
                    TextField {
                        id: customAspectRatioYTextField
                        placeholderText: "Y (e.g. 16)"
                        validator: IntValidator { bottom: 1 }
                    }
                }
                Row {
                    visible: aspectRatioOptionsModel.get(aspectRatioComboBox.currentIndex).settingsId === "custom"
                    spacing: 4
                    Label {
                        height: customAspectRatioXTextField.height
                        text: "X:"
                        verticalAlignment: Text.AlignVCenter
                    }
                    TextField {
                        id: customAspectRatioXTextField
                        placeholderText: "X (e.g. 9)"
                        validator: IntValidator { bottom: 1 }
                    }
                }

                Label {
                    height: layoutBreaksModeComboBox.height
                    text: "Line/Page breaks:"
                    verticalAlignment: Text.AlignVCenter
                }

                ComboBox {
                    id: layoutBreaksModeComboBox
                    currentIndex: 1
                    model: ListModel {
                        id: layoutBreaksModeOptionsModel
                        ListElement { settingsId: "remove"; text: "Don't export"; mode: "remove" }
                        ListElement { settingsId: "reflow"; text: "Export line breaks, reflow other layout"; mode: "reflow" }
                        ListElement { settingsId: "keep"; text: "Export the original line and page breaks structure (usually not recommended)"; mode: "keep" }
                    }
                    Layout.fillWidth: true
                }
            }
        }

        function findModelIndexBySettingsId(model, settingsId) {
            var count = model.count;

            for (var i = 0; i < count; ++i) {
                if (model.get(i).settingsId == settingsId) {
                    return i;
                }
            }

            return 0;
        }

        onVisibleChanged: {
            if (visible) {
                if (pluginSettings.selectedLayoutMode == layoutModeRadioButtonAdapt.settingsId) {
                    layoutModeRadioButtonAdapt.checked = true;
                } else if (pluginSettings.selectedLayoutMode == layoutModeRadioButtonPreserve.settingsId) {
                    layoutModeRadioButtonPreserve.checked = true;
                }
                aspectRatioComboBox.currentIndex = findModelIndexBySettingsId(aspectRatioComboBox.model, pluginSettings.selectedAspectRatio);
                customAspectRatioXTextField.text = pluginSettings.customAspectRatioX;
                customAspectRatioYTextField.text = pluginSettings.customAspectRatioY;
                layoutBreaksModeComboBox.currentIndex = findModelIndexBySettingsId(layoutBreaksModeComboBox.model, pluginSettings.selectedLayoutBreakMode);
            }
        }

        onAccepted: {
            var layoutMode = layoutModeGroup.current.settingsId;
            var aspectRatio = aspectRatioOptionsModel.get(aspectRatioComboBox.currentIndex);
            var layoutBreaksMode = layoutBreaksModeOptionsModel.get(layoutBreaksModeComboBox.currentIndex);
            var settings = {
                "layoutMode": layoutMode,
                "aspectRatio": {
                    "x": aspectRatio.x ? aspectRatio.x : +customAspectRatioXTextField.text,
                    "y": aspectRatio.y ? aspectRatio.y : +customAspectRatioYTextField.text,
                },
                "layoutBreaksMode": layoutBreaksMode.mode,
            };

            if (settings.aspectRatio.x <= 0 || settings.aspectRatio.y <= 0) {
                messageDialog.showError("Invalid aspect ratio", "Please enter valid aspect ratio.", function() { open(); });
            } else {
                // If called without callLater(), the dialog opens
                // somewhere behind the main window.
                Qt.callLater(function() { plugin.openSaveFileDialog(settings) });
            }

            // Save the selected export settings.
            pluginSettings.selectedLayoutMode = layoutMode;
            pluginSettings.selectedAspectRatio = aspectRatio.settingsId;
            pluginSettings.customAspectRatioX = customAspectRatioXTextField.text;
            pluginSettings.customAspectRatioY = customAspectRatioYTextField.text;
            pluginSettings.selectedLayoutBreakMode = layoutBreaksMode.settingsId;
        }
    }

    MessageDialog {
        id: messageDialog
        icon: StandardIcon.Warning
        title: dialogTitle
        modality: Qt.ApplicationModal
        standardButtons: StandardButton.Ok

        // For some reason the dialog's title setter doesn't work,
        // so we update it via a property binding.
        property string dialogTitle: plugin.name
        property var onClosedCallback: null

        function showError(title, message, callback) {
            icon = StandardIcon.Critical;
            dialogTitle = title;
            text = message;
            onClosedCallback = callback ? callback : null;
            open();
        }

        function showInfo(title, message, callback) {
            icon = StandardIcon.Information;
            dialogTitle = title;
            text = message;
            onClosedCallback = callback ? callback : null;
            open();
        }

        onAccepted: {
            if (onClosedCallback) {
                onClosedCallback();
            }
        }
    }

    function findPage(e) {
        while (e && e.type != Element.PAGE)
            e = e.parent;
        return e;
    }

    function findSystem(e) {
        while (e && e.type != Element.SYSTEM)
            e = e.parent;
        return e;
    }

    function formatTagWithAttributes(name, attributes, standalone /* = false */) {
        var parts = ["<", name];

        if (attributes) {
            for (var attr in attributes) {
                parts.push(" ");
                parts.push(attr);
                parts.push("=\"");
                parts.push(attributes[attr]);
                parts.push("\"");
            }
        }

        if (standalone)
            parts.push(" />");
        else
            parts.push(">");

        return parts.join("");
    }

    function formatStartTag(name, attributes) {
        return formatTagWithAttributes(name, attributes, false);
    }

    function formatStandaloneTag(name, attributes) {
        return formatTagWithAttributes(name, attributes, true);
    }

    function formatEndTag(name) {
        return "</" + name + ">";
    }

    function formatTag(name, value) {
        var parts = ["<", name, ">", value, "</", name, ">"];
        return parts.join("");
    }

    function formatCDataTag(name, data) {
        // Escape possible CDATA entries in data.
        data = data.replace(/]]>/g, "]]]]><![CDATA[>");

        var tagDataParts = ["<![CDATA[", data, "]]>"];
        return formatTag(name, tagDataParts.join(""));
    }

    function getMuseScoreVersionString() {
        return mscoreMajorVersion + "." + mscoreMinorVersion + "." + mscoreUpdateVersion;
    }

    function generateTemporaryFilePath() {
        var randomString = Math.random().toString(36).substring(2);
        var basename = plugin.internalName + "_" + randomString;
        var tmpdir = fileIO.tempPath();
        return tmpdir + "/" + basename;
    }

    function getConvertedScoreData(score, format, multipleFiles) {
        var fullBasePath = generateTemporaryFilePath();
        var ok = plugin.writeScore(score, fullBasePath, format);

        if (!ok)
            throw new Error("Failed to export score to '" + format + "'");

        function processTemporaryFile(filePath) {
            fileIO.source = filePath;

            if (!fileIO.exists())
                return;

            var data = fileIO.read();

            // Cleanup the temporary file.
            fileIO.remove();

            return data;
        }

        var filesContentList = []

        if (multipleFiles) {
            function padNumber(n, size) {
                var str = n.toString();
                while (str.length < size)
                    str = "0" + str;
                return str;
            }

            function getFilename(n, padding) {
                var numStr = padNumber(i, padding);
                return [fullBasePath, "-", numStr, ".", format].join("");
            }

            var numberPadding = 1;

            // Probe for padding.
            // TODO: better use FolderListModel? It works asynchronously though.
            for (var i = 1; i < 5; ++i) {
                fileIO.source = getFilename(1, i);
                if (fileIO.exists()) {
                    numberPadding = i;
                    break;
                }
            }

            var maxPages = 10000;
            // MuseScore saves images to files like <score_name>-1.svg, <score_name>-2.svg etc.
            for (var i = 1; i < maxPages; ++i) {
                var filePath = getFilename(i, numberPadding);
                var fileContent = processTemporaryFile(filePath);

                if (fileContent)
                    filesContentList.push(fileContent);
                else
                    break;
            }
        } else {
            var filePath = [fullBasePath, ".", format].join("");
            var fileContent = processTemporaryFile(filePath);

            if (fileContent)
                filesContentList.push(fileContent);
        }

        if (!filesContentList.length)
            throw new Error("Failed to get data for '" + format + "' format");

        return filesContentList;
    }

    function getMusicXmlForScore(score) {
        var dataList = getConvertedScoreData(score, "musicxml", false);
        return dataList[0];
    }

    function getSvgsForScore(score) {
        return getConvertedScoreData(score, "svg", true);
    }

    function getCreatorXmlLines() {
        var lines = [
            "<creator>",
            "  <source>",
            "    <name>MuseScore</name>",
            "    <version>" + getMuseScoreVersionString() + "</version>",
            "  </source>",
            "  <exporter>",
            "    <name>" + plugin.name + "</name>",
            "    <version>" + plugin.version + "</version>",
            "  </exporter>",
            "</creator>",
        ];
        return lines;
    }

    function getMetadataXmlLines(score) {
        var lines = [];

        function addTagIfPresent(muName, smlName) {
            var value = score.metaTag(muName);
            if (value != "") {
                var tag = "tag";
                var tokens = [formatStartTag(tag, {"name": smlName}), value, formatEndTag(tag)];
                lines.push(tokens.join(""));
            }
        }

        var metadataTag = "metadata";
        lines.push(formatStartTag(metadataTag));
        // It seems there is no way to get a list of available
        // tags, so add only those we will most likely need.
        addTagIfPresent("workTitle", "title");
        addTagIfPresent("composer", "composer");
        addTagIfPresent("copyright", "copyright");
        addTagIfPresent("source", "source");
        lines.push(formatEndTag(metadataTag));

        // Don't add empty metadata.
        return (lines.length > 2) ? lines : [];
    }

    function getMeasureBbox(m, score) {
        var mBbox = m.bbox;
        var mPagePos = m.pagePos;
        // Convert to a JS object to be able to change its properties.
        var bbox = {
            "x": mBbox.x + mPagePos.x,
            "y": mBbox.y + mPagePos.y,
            "width": mBbox.width,
            "height": mBbox.height
        };

        var bboxTop = bbox.y;
        var bboxBottom = bboxTop + bbox.height;

        var ntracks = score.ntracks;

        function addToBbox(e) {
            if (!e || !e.visible)
                return;

            var eBbox = e.bbox;
            var ePagePos = e.pagePos;

            // Change only vertical boundaries: horizontal are OK in the standard bbox.
            var eTop = eBbox.y + ePagePos.y;
            var eBottom = eTop + eBbox.height;

            if (eTop < bboxTop)
                bboxTop = eTop;
            if (eBottom > bboxBottom)
                bboxBottom = eBottom;
        }

        function addListToBbox(elements) {
            for (var ei = 0; ei < elements.length; ++ei) {
                addToBbox(elements[ei]);
            }
        }

        function addNoteToBbox(note) {
            addToBbox(note);
            addToBbox(note.accidental);
            addListToBbox(note.dots);
            addListToBbox(note.elements);
        }

        for (var seg = m.firstSegment; seg; seg = seg.nextInMeasure) {
            for (var track = 0; track < ntracks; ++track) {
                var e = seg.elementAt(track);
                var type = e ? e.type : Element.INVALID;

                switch (type) {
                    case Element.CHORD:
                        var notes = e.notes;
                        for (var ni = 0; ni < notes.length; ++ni) {
                            addNoteToBbox(notes[ni]);
                        }

                        var graceChords = e.graceNotes;
                        for (var gi = 0; gi < graceChords.length; ++gi) {
                            var graceChord = graceChords[gi];
                            var graceNotes = graceChord.notes;
                            for (var gni = 0; gni < graceNotes.length; ++gni) {
                                addNoteToBbox(graceNotes[gni]);
                            }
                        }

                        addToBbox(e.stem);
                        addToBbox(e.hook);
                        addToBbox(e.tuplet);
                        addToBbox(e.beam);
                        addListToBbox(e.lyrics);
                        break;
                    case Element.REST:
                        addToBbox(e);
                        addToBbox(e.tuplet);
                        addToBbox(e.beam);
                        addListToBbox(e.lyrics);
                        break;
                    case Element.CLEF:
                    case Element.KEYSIG:
                    case Element.TIMESIG:
                        addToBbox(e);
                }
            }

            var annotations = seg.annotations;
            for (var ai = 0; ai < annotations.length; ++ai) {
                addToBbox(annotations[ai]);
            }
        }

        addListToBbox(m.elements);

        // Add extra space above and below the element boxes.
        bboxTop -= 1.0;
        bboxBottom += 1.0;

        bbox.y = bboxTop;
        bbox.height = bboxBottom - bboxTop;

        return bbox;
    }

    function alignSystemBoxes(measures) {
        var prevSystem = [];
        var curSystem = [];
        var curSystemIndex = 0;

        function alignSystems(curSystem, prevSystem) {
            if (curSystem.length > 0) {
                // Define top and bottom for the current system.
                var sysTop = 1e30;
                var sysBottom = -1e30;

                for (var ci = 0; ci < curSystem.length; ++ci) {
                    var cmTop = curSystem[ci].bbox.y;
                    var cmBottom = cmTop + curSystem[ci].bbox.height;

                    if (cmTop < sysTop)
                        sysTop = cmTop;
                    if (cmBottom > sysBottom)
                        sysBottom = cmBottom;
                }

                // Check a possible overlap with the previous system.
                // TODO: how to handle it better?
                if (prevSystem.length > 0 && prevSystem[0].page == curSystem[0].page) {
                    var prevSystemTop = prevSystem[0].bbox.y;
                    var prevSystemBottom = prevSystemTop + prevSystem[0].bbox.height;

                    if (sysTop < prevSystemBottom) {
                        prevSystemBottom = Math.max(prevSystemTop, (sysTop + prevSystemBottom) / 2);
                        sysTop = prevSystemBottom;

                        // Apply the corrected boundary for the previous system.
                        for (var pi = 0; pi < prevSystem.length; ++pi) {
                            prevSystem[pi].bbox.height = prevSystemBottom - prevSystemTop;
                        }
                    }
                }

                // Apply the final system boundaries.
                for (var ci = 0; ci < curSystem.length; ++ci) {
                    var cm = curSystem[ci];
                    cm.bbox.y = sysTop;
                    cm.bbox.height = sysBottom - sysTop;
                }
            }
        }

        for (var mi = 0; mi < measures.length; ++mi) {
            var m = measures[mi];

            if (m.system == curSystemIndex) {
                curSystem.push(m);
            } else {
                alignSystems(curSystem, prevSystem);
                prevSystem = curSystem;
                curSystem = [m];
                curSystemIndex = m.system;
            }
        }

        // Align the last system.
        alignSystems(curSystem, prevSystem);
    }

    function addLayoutXmlLines(lines, score) {
        var layoutTagName = "layout";
        lines.push(formatStartTag(layoutTagName));

        var style = score.style;

        var pixelsPerSpatium = style.value("spatium"); // in internal DPI pixels
        var pixelsPerInch = plugin.mscoreDPI; // internal DPI in MuseScore
        var pointsPerInch = 72;
        var pointsPerSpatium = pointsPerInch / pixelsPerInch * pixelsPerSpatium;

        var pageWidthInches = style.value("pageWidth");
        var pageHeightInches = style.value("pageHeight");

        lines.push(formatStartTag("page-format"));
        lines.push(formatTag("width", pageWidthInches * pointsPerInch));
        lines.push(formatTag("height", pageHeightInches * pointsPerInch));
        lines.push(formatTag("margin-left", style.value("pageOddLeftMargin") * pointsPerInch));
        lines.push(formatTag("margin-right", (style.value("pageWidth") - style.value("pageOddLeftMargin") - style.value("pagePrintableWidth")) * pointsPerInch));
        lines.push(formatTag("margin-top", style.value("pageOddTopMargin") * pointsPerInch));
        lines.push(formatTag("margin-bottom", style.value("pageOddBottomMargin") * pointsPerInch));
        lines.push(formatEndTag("page-format"));

        if (style.value("pageEvenLeftMargin") != style.value("pageOddLeftMargin")
            || style.value("pageEvenTopMargin") != style.value("pageOddTopMargin")
            || style.value("pageEvenBottomMargin") != style.value("pageOddBottomMargin")) {
            var iExceptionalPageStart = Math.abs(1 + score.pageNumberOffset) % 2;
            var nPages = score.npages;

            for (var iPage = iExceptionalPageStart; iPage < nPages; iPage += 2) {
                lines.push(formatStartTag("page-format", {"page": iPage}));
                lines.push(formatTag("margin-left", style.value("pageEvenLeftMargin") * pointsPerInch));
                lines.push(formatTag("margin-right", (style.value("pageWidth") - style.value("pageEvenLeftMargin") - style.value("pagePrintableWidth")) * pointsPerInch));
                lines.push(formatTag("margin-top", style.value("pageEvenTopMargin") * pointsPerInch));
                lines.push(formatTag("margin-bottom", style.value("pageEvenBottomMargin") * pointsPerInch));
                lines.push(formatEndTag("page-format"));
            }
        }

        lines.push(formatStartTag("measures"));

        var prevSystem = null;
        var systemNumber = -1;

        var measures = [];

        for (var m = score.firstMeasureMM; m; m = m.nextMeasureMM) {
            var bbox = getMeasureBbox(m, score);

            var fs = m.firstSegment;
            var tick = fs ? fs.tick : -1;

            var system = findSystem(m);
            if (!system.is(prevSystem)) {
                ++systemNumber;
                prevSystem = system;
            }

            var measure = {
                "tick": tick,
                "bbox": {
                    "x": bbox.x * pointsPerSpatium,
                    "y": bbox.y * pointsPerSpatium,
                    "width": bbox.width * pointsPerSpatium,
                    "height": bbox.height * pointsPerSpatium,
                },
                "page": findPage(system).pagenumber,
                "system": systemNumber,
            };

            measures.push(measure);
        }

        alignSystemBoxes(measures);

        for (var mi = 0; mi < measures.length; ++mi) {
            var m = measures[mi];
            lines.push(formatStartTag("measure", {"page": m.page, "system": m.system}));
            lines.push(formatTag("tick", m.tick));
            lines.push(formatStandaloneTag("page-rect", m.bbox));
            lines.push(formatEndTag("measure"));
        }

        lines.push(formatEndTag("measures"));

        lines.push(formatStartTag("images"));
        var images = getSvgsForScore(score);
        for (var i = 0; i < images.length; ++i) {
            lines.push(formatCDataTag("svg", images[i]));
        }
        lines.push(formatEndTag("images"));

        lines.push(formatEndTag(layoutTagName));
        return lines;
    }

    function preprocessScore(score, exportSettings) {
        var undoLevel = 0;
        var elementsToRemove = [];

        if (exportSettings.layoutBreaksMode == "remove") {
            for (var m = score.firstMeasureMM; m; m = m.nextMeasureMM) {
                var elements = m.elements;
                for (var i = 0; i < elements.length; ++i) {
                    var e = elements[i];
                    if (e.type == Element.LAYOUT_BREAK && e.layoutBreakType != LayoutBreak.SECTION && e.layoutBreakType != LayoutBreak.NOBREAK) {
                        elementsToRemove.push(e);
                    }
                }
            }
        }

        if (elementsToRemove.length > 0) {
            score.startCmd();
            for (var i = 0; i < elementsToRemove.length; ++i) {
                removeElement(elementsToRemove[i]);
            }
            score.endCmd();
            ++undoLevel;
        }

        return undoLevel;
    }

    function reflowMeasuresBetweenBreaks(score) {
        var undoLevel = 0;
        var measures = [];
        var lineBreaksToRemove = [];
        var measuresToBreak = [];

        function collectLastSystem(measures) {
            if (measures.length == 0) {
                return [];
            }

            var system = findSystem(measures[measures.length - 1]);
            var systemMeasures = [];

            for (var i = measures.length - 1; i >= 0; --i) {
                var m = measures[i];
                if (!findSystem(m).is(system))
                    break;
                systemMeasures.push(m);
            }

            systemMeasures.reverse();
            return systemMeasures;
        }

        function reflowMeasures(measures) {
            var lastSystemMeasures = collectLastSystem(measures);
            var reflowMeasures = measures;

            while (lastSystemMeasures.length > 0) {
                reflowMeasures = reflowMeasures.slice(0, -lastSystemMeasures.length);
                var prevSystemMeasures = collectLastSystem(reflowMeasures);

                var measureCountDiff = prevSystemMeasures.length - lastSystemMeasures.length;
                var minMeasureCountDiff = lastSystemMeasures.length / 2 + 0.001;
                var measuresToMoveCount = Math.floor(measureCountDiff / 2);

                if (measureCountDiff >= minMeasureCountDiff) {
                    var breakMeasure = prevSystemMeasures[prevSystemMeasures.length - 1 - measuresToMoveCount];

                    // A measure may have a "no break" element. In that case respect it.
                    var isLayoutBreakForbidden = false;
                    var breakMeasureElements = breakMeasure.elements;
                    for (var i = 0; i < breakMeasureElements.length; ++i) {
                        var e = breakMeasureElements[i];
                        if (e.type == Element.LAYOUT_BREAK && e.layoutBreakType == LayoutBreak.NOBREAK) {
                            isLayoutBreakForbidden = true;
                            break;
                        }
                    }

                    if (!isLayoutBreakForbidden) {
                        measuresToBreak.push(breakMeasure);
                    }
                }

                lastSystemMeasures = prevSystemMeasures;
            }
        }

        for (var m = score.firstMeasureMM; m; m = m.nextMeasureMM) {
            measures.push(m);

            var layoutBreak = null;
            var measureElements = m.elements;
            for (var i = 0; i < measureElements.length; ++i) {
                var e = measureElements[i];
                if (e.type == Element.LAYOUT_BREAK && e.layoutBreakType != LayoutBreak.NOBREAK) {
                    layoutBreak = e;
                    // Page breaks should be replaced by line breaks.
                    if (layoutBreak.layoutBreakType == LayoutBreak.PAGE) {
                        lineBreaksToRemove.push(layoutBreak);
                        measuresToBreak.push(m);
                    }
                    break;
                }
            }

            if (layoutBreak) {
                reflowMeasures(measures);
                measures = [];
            }
        }

        // Handle the last set of measures.
        reflowMeasures(measures);

        if (lineBreaksToRemove.length > 0 || measuresToBreak.length > 0) {
            score.startCmd();

            for (var i = 0; i < lineBreaksToRemove.length; ++i) {
                removeElement(lineBreaksToRemove[i]);
            }

            var cursor = score.newCursor();
            for (var i = 0; i < measuresToBreak.length; ++i) {
                var seg = measuresToBreak[i].firstSegment;
                if (!seg)
                    continue;

                cursor.rewindToTick(seg.tick);
                var lb = newElement(Element.LAYOUT_BREAK);
                lb.layoutBreakType = LayoutBreak.LINE;
                cursor.add(lb);
            }

            score.endCmd();
            ++undoLevel;
        }

        return undoLevel;
    }

    function preprocessScoreLayout(score, layout, exportSettings) {
        var undoLevel = 0;
        var layoutSettingsCount = Object.keys(layout).length;

        if (layoutSettingsCount) {
            score.startCmd();
            var style = score.style;
            for (var key in layout) {
                style.setValue(key, layout[key]);
            }
            score.endCmd();
            ++undoLevel;

            if (exportSettings.layoutBreaksMode == "reflow") {
                undoLevel += reflowMeasuresBetweenBreaks(score);
            }
        }

        return undoLevel;
    }

    function addLayouts(lines, score, layouts, exportSettings) {
        if (!layouts || !layouts.length) {
            addLayoutXmlLines(lines, score);
            return;
        }

        if (!score.is(curScore)) {
            throw new Error("Only current score can be exported");
        }

        var commonUndoLevel = preprocessScore(score, exportSettings);

        for (var li = 0; li < layouts.length; ++li) {
            var layout = layouts[li];
            var layoutUndoLevel = preprocessScoreLayout(score, layout, exportSettings);

            addLayoutXmlLines(lines, score);

            for (var i = 0; i < layoutUndoLevel; ++i) {
                cmd("undo");
            }
        }

        for (var i = 0; i < commonUndoLevel; ++i)  {
            cmd("undo");
        }
    }

    function getDocumentXml(score, layouts, exportSettings) {
        var lines = ['<?xml version="1.0" encoding="UTF-8"?>'];

        var rootName = "smlxml";
        var fileFormatVersion = "1.0.0";
        lines.push(formatStartTag(rootName, { "version": fileFormatVersion }));

        Array.prototype.push.apply(lines, getCreatorXmlLines());
        Array.prototype.push.apply(lines, getMetadataXmlLines(score));

        lines.push(formatStartTag("global"));
        lines.push(formatTag("ticks-per-quarter", plugin.division));
        lines.push(formatEndTag("global"));

        lines.push(formatStartTag("score"));
        lines.push(formatCDataTag("musicxml", getMusicXmlForScore(score)));
        lines.push(formatEndTag("score"));

        var layoutsContainerName = "layouts";
        lines.push(formatStartTag(layoutsContainerName));
        addLayouts(lines, score, layouts, exportSettings);
        lines.push(formatEndTag(layoutsContainerName));

        lines.push(formatEndTag(rootName));
        return lines.join("\n");
    }

    function getLayoutSettings(diagonalInches, aspectRatio) {
        var xRatio = aspectRatio.x;
        var yRatio = aspectRatio.y;
        var cmPerInch = 2.54;
        var marginCm = 0.2;

        var baseUnitDiv = Math.sqrt(xRatio*xRatio + yRatio*yRatio);
        var baseUnitInches = diagonalInches / baseUnitDiv;

        var layout = {};
        layout["pageWidth"] = xRatio * baseUnitInches;
        layout["pageHeight"] = yRatio * baseUnitInches;
        layout["pageEvenLeftMargin"] = marginCm / cmPerInch;
        layout["pageOddLeftMargin"] = marginCm / cmPerInch;
        layout["pageEvenTopMargin"] = marginCm / cmPerInch;
        layout["pageEvenBottomMargin"] = marginCm / cmPerInch;
        layout["pageOddTopMargin"] = marginCm / cmPerInch;
        layout["pageOddBottomMargin"] = marginCm / cmPerInch;
        var rightMarginInches = marginCm / cmPerInch;
        layout["pagePrintableWidth"] = layout["pageWidth"] - layout["pageOddLeftMargin"] - rightMarginInches;

        layout["hideInstrumentNameIfOneInstrument"] = true;

        return layout;
    }

    function exportScore(score, outPath, exportSettings) {
        var layouts = [];

        if (exportSettings.layoutMode == "adapt") {
            layouts = [
                getLayoutSettings(10.1, exportSettings.aspectRatio),
                getLayoutSettings(8.0, exportSettings.aspectRatio),
                getLayoutSettings(12.625, exportSettings.aspectRatio),
            ];
        } else if (exportSettings.layoutMode == "preserve") {
            layouts = [
                {}, // original score layout
            ];
        } else {
            throw new Error("Unknown layoutMode value: " + exportSettings.layoutMode);
        }

        var tmpBasePath = generateTemporaryFilePath();
        var tmpUncompressedFile = tmpBasePath + ".smlxml";
        var tmpCompressedFile = tmpBasePath + exportedFileSuffix;
        var exportDone = false;

        try {
            var xml = getDocumentXml(score, layouts, exportSettings);

            fileIO.source = tmpUncompressedFile;
            console.log("Export to a temporary file:", fileIO.source);
            var ok = fileIO.write(xml);
            if (!ok) {
                throw new Error("Failed to create a temporary file at %1".arg(fileIO.source));
            }

            qprocess.makeGzipFile(tmpUncompressedFile, tmpCompressedFile);
            qprocess.moveFile(tmpCompressedFile, outPath);

            fileIO.source = outPath;
            exportDone = fileIO.exists();
        } catch (e) {
            console.log("Error:", e.message);
            messageDialog.showError("Error", e.message);
        }

        // Cleanup.
        var cleanupFiles = [tmpUncompressedFile, tmpCompressedFile];

        for (var i = 0; i < cleanupFiles.length; ++i) {
            fileIO.source = cleanupFiles[i];
            if (fileIO.exists()) {
                fileIO.remove();
            }
        }

        if (exportDone) {
            console.log("Successfully exported to", outPath);
            messageDialog.showInfo("Success", "Successfully exported to\n" + outPath);
        }
    }

    function openSaveFileDialog(exportSettings) {
        var scorePath = curScore.path;
        var defaultExportPath = "";

        if (scorePath && scorePath != "" && !scorePath.startsWith(":")) {
            var defaultExportPath = scorePath.replace(/\.[0-9A-Za-z]+$/, exportedFileSuffix);
        }

        if (defaultExportPath != "") {
            exportFileDialog.folder = Qt.resolvedUrl(defaultExportPath); // TODO: doesn't seem to work (at least on Linux)
        }

        exportFileDialog.score = curScore;
        exportFileDialog.exportSettings = exportSettings;
        exportFileDialog.openSaveFileDialog();

        if (exportFileDialog.platformDialog) {
            exportFileDialog.platformDialog.currentFile = Qt.resolvedUrl(defaultExportPath);
        }
    }

    function getCommandLineArguments() {
        var args = Qt.application.arguments;
        var searchString = "smartleggio-export-args=";

        for (var i = 0; i < args.length; ++i) {
            var arg = args[i];

            if (arg.startsWith(searchString)) {
                arg = arg.substr(searchString.length);
                return JSON.parse(arg);
            }
        }

        return null;
    }

    function processCommandLineConversion(args) {
        if (!args.outFile) {
            console.log(plugin.name + ": Missing required argument: outFile");
            return;
        }
        if (!args.settings) {
            args.settings = {};
        }
        if (!args.settings.layoutMode) {
            args.settings.layoutMode = "adapt";
        }
        if (!args.settings.layoutBreaksMode) {
            args.settings.layoutBreaksMode = "remove";
        }
        if (!args.settings.aspectRatio) {
            args.settings.aspectRatio = {"y": 4, "x": 3};
        }
        plugin.exportScore(plugin.curScore, args.outFile, args.settings);
    }

    onRun: {
        if (mscoreVersion < 30602) {
            var msg = "MuseScore 3.6.2 is required to run this plugin";
            console.log(msg);
            messageDialog.showError("Version error", msg);
            return;
        }

        // Check for command-line arguments for batch operation.
        // Usage: musescore input_score.mscz -p Smartleggio_MuseScore_Plugin/SmartleggioExport.qml --highlight-config 'smartleggio-export-args={"settings": {"aspectRatio": {"y": 4, "x": 3}}, "outFile": "out.smlgz"}'
        // --highlight-config is a dummy argument to get MuseScore's command line parser satisfied.
        var args = getCommandLineArguments();
        if (args) {
            processCommandLineConversion(args);
            return;
        }

        exportSettingsDialog.open();
    }
}
