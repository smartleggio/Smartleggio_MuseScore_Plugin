# Smartleggio plugin for MuseScore
A plugin for MuseScore for exporting scores to the [Smartleggio](https://smartleggio.com/)'s `.smlgz` file format.

Currently supports MuseScore 3.6.2. Support for MuseScore 4 is a work in progress, the plugin infrastructure of the currently available versions of MuseScore 4 does not yet support the features necessary for this plugin.

## Motivation
[Smartleggio](https://smartleggio.com/) is a sheet music reading application which can read scores in MusicXML and PDF file formats. MuseScore supports exporting scores to these formats without the need for plugins. However both file formats have their downsides:
- Conversion to MusicXML is lossy:
  - Not all score features used by the notation software are supported;
  - Layout infromation is limited;
  - MusicXML rendering in applications (like Smartleggio) may be different from the original look of the score;
- PDF is not friendly for digital score readers:
  - No music content information is included, it has to be reconstructed via OMR which is likely to introduce errors;
  - Scaling and adjustment to the display's aspect ratio is not possible.

The `smlgz` file format created for Smartleggio tries to circumvent those downsides:
- It includes the music content infromation, so digital features like playback and automatic page turn are possible;
- It includes pre-rendered images of the score, so rendernig will not be different from the original look of the score;
- It can be optimized for a certain aspect ratio of a display;
- It can include data for different scales, so that the reader application is able to scale the content.

This plugin adds a possibility to export scores to the `smlgz` file format from MuseScore.

## Installation
For MuseScore 3:
1. Download the plugin at [this link](https://github.com/smartleggio/Smartleggio_MuseScore_Plugin/releases/latest/download/Smartleggio_MuseScore_Plugin.zip);
2. Extract the downloaded archive to the MuseScore's plugins directory:
  - Windows: `C:\Users\<Username>\Documents\MuseScore3\Plugins`
  - macOS: `~/Documents/MuseScore3/Plugins`
  - Linux: `~/Documents/MuseScore3/Plugins`
3. Start (or restart) MuseScore;
4. Select menu Plugins → Plugin Manager;
5. Find the `SmartleggioExport` plugin and tick the corresponding checkbox to enable it.

## Usage
1. Open the score you would like to export;
2. Select menu Plugins → Smartleggio Export;
3. In the dialog that appears choose the necessary export settings and press Save;
4. Choose the location and the name of the file to save.

On successful export the message "Successfully exported to \<file path\>" should appear.

The exported file can then be copied to a tablet or smartphone and opened with Smartleggio.
