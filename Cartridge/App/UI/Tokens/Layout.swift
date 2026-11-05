import CoreGraphics

enum Space {
    static let half: CGFloat = 2
    static let n1: CGFloat = 4
    static let n2: CGFloat = 8
    static let n3: CGFloat = 12
    static let n4: CGFloat = 16
    static let n5: CGFloat = 24
    static let n6: CGFloat = 32
    static let n7: CGFloat = 48
    static let n8: CGFloat = 64
    static let n9: CGFloat = 96
}

enum Layout {
    static let titlebarHeight: CGFloat = 28
    static let windowMinWidth: CGFloat = 1280
    static let windowMinHeight: CGFloat = 800
    static let marginX: CGFloat = 80
    static let topbarHeight: CGFloat = 48
    static let shellItemHeight: CGFloat = 40
    static let shellGlyph: CGFloat = 18
    static let shellChevron: CGFloat = 13
    static let heroHeight: CGFloat = 330
    static let backdropHeightFraction: CGFloat = 0.7
    static let consoleFrameArtShare: CGFloat = 0.72
    static let consoleFrameInset: CGFloat = 34
    static let consoleFrameEdge: CGFloat = 2
    static let consoleFrameArtLift: CGFloat = 24
    static let consoleFrameArtExtension: CGFloat = 80
    static let consoleFrameDetailStrength: Double = 0.62
    static let consoleCardSheen: Double = 0.18
    static let consoleCardGlow: CGFloat = 20
    static let consoleStripeHeight: CGFloat = 6
    static let backdropImageShare: CGFloat = 0.74
    static let backdropDriftScale: CGFloat = 1.06
    static let detailDim: Double = 0.5
    static let scanlinePitch: CGFloat = 4
    static let scanlineThickness: CGFloat = 1.5
    static let backdropBlur: CGFloat = 3
    static let backdropBlurHeavy: CGFloat = 28
    static let heroTextMax: CGFloat = 860
    static let railWidth: CGFloat = 300
    static let rowLabelHeight: CGFloat = 30
    static let rowLabelGap: CGFloat = 14
    static let rowGap: CGFloat = 18
    static let tileHeight: CGFloat = 150
    static let momentWidth: CGFloat = 267
    static let momentCoverHeight: CGFloat = 64
    static let pickWidth: CGFloat = 480
    static let shelfDrop: CGFloat = 60
    static let consoleBackdropFadeStart: CGFloat = 0.7
    static let consoleBackdropHeight: CGFloat = 0.78
    static let consoleHeroWidth: CGFloat = 760
    static let consoleHeroHeight: CGFloat = 280
    static let gridGap: CGFloat = 26
    static let galleryGlyph: CGFloat = 56
    static let artFillBlur: CGFloat = 18
    static let focusBleed: CGFloat = 24
    static let introBurstRadius: CGFloat = 900
    static let padKey: CGFloat = 56
    static let padWidth: CGFloat = 420
    static let searchCellWidth: CGFloat = 215
    static let caretWidth: CGFloat = 4
    static let caretHeight: CGFloat = 48
    static let rowHeight = rowLabelHeight + rowLabelGap + tileHeight
    static let rowPitch = rowHeight + rowGap
    static let tileGap: CGFloat = 16
    static let tilesBeforeHighlight = 2
    static let hintbarHeight: CGFloat = 64
    static let bandHeight: CGFloat = 64
    static let panelBodyMax: CGFloat = 760
    static let measure: CGFloat = 660
    static let noteMax: CGFloat = 320
    static let chipHeight: CGFloat = 40
    static let buttonMinHeight: CGFloat = 72
    static let rowMinHeight: CGFloat = 76
    static let keycapHeight: CGFloat = 30
    static let keycapMinWidth: CGFloat = 30
    static let launchIcon: CGFloat = 160
    static let welcomeIcon: CGFloat = 128
    static let welcomeWidth: CGFloat = 900
    static let wordmarkIconSmall: CGFloat = 28
    static let markWidth: CGFloat = 22
    static let progressWidth: CGFloat = 560
    static let progressHeight: CGFloat = 6
    static let railMarkerWidth: CGFloat = 4
    static let systemChipGridWidth: CGFloat = 600
    static let systemChipColumns = 3
    static let settingsLeftWidth: CGFloat = 520
    static let strokeHair: CGFloat = 1
    static let panelCanvas = CGSize(width: 1440, height: 900)
    static let panelBodyWidth: CGFloat = 620
    static let panelMomentBottom: CGFloat = 196
    static let panelNoteWidth: CGFloat = 520
    static let panelNoteMinHeight: CGFloat = 44
    static let panelFloorY: CGFloat = 748
    static let panelArtCenterX: CGFloat = 1074
    static let panelArtCenterXMoment: CGFloat = 1140
    static let panelArtSize: CGFloat = 488
    static let panelArtSizeMoment: CGFloat = 384
    static let panelArtWideShare: CGFloat = 1.08
    static let panelArtSquareShare: CGFloat = 0.8
    static let panelInsertBoxHeight: CGFloat = 380
    static let panelInsertDim = 0.6
    static let panelInsertDimConsole = 0.78
    static let panelInsertCaptionDrop: CGFloat = 56
    static let panelInsertCaptionGap: CGFloat = 16
    static let panelInsertChromeShift: CGFloat = 16
    static let caseCamera: CGFloat = 1700
    static let caseEyeLift: CGFloat = 0.1
    static let casePoolDepth: CGFloat = 210
    static let casePoolLift: CGFloat = 28
    static let caseContactHeight: CGFloat = 26
    static let caseContactBlur: CGFloat = 3
    static let momentFocusY: CGFloat = 0.62
    static let momentScrimLeft: Double = 0.62
    static let momentScrimLeftEnd: CGFloat = 0.5
    static let momentScrimBottom: Double = 0.86
    static let momentScrimBottomStart: CGFloat = 0.46
    static let momentScrimTop: Double = 0.5
    static let momentScrimTopHeight: CGFloat = 150
    static let cardHeight: CGFloat = 152
    static let thumbHeight: CGFloat = 80
    static let messageWidth: CGFloat = 520
    static let sheetInsetX: CGFloat = 48
    static let sheetBottom: CGFloat = 32
    static let creditLabelWidth: CGFloat = 260
    static let glyphCard: CGFloat = 32
    static let sheetRise: CGFloat = 24
    static let blurSheet: CGFloat = 34
    static let saturateSheet: Double = 1.5
    static let strokeKeycap: CGFloat = 1.5

    static let glyphHint: CGFloat = 28
    static let glyphStatus: CGFloat = 26
    static let glyphInline: CGFloat = 22
    static let glyphMessage: CGFloat = 32

    static let spinner: CGFloat = 18
    static let spinnerStroke: CGFloat = 2

    static let blurMaterial: CGFloat = 30
    static let blurAmbient: CGFloat = 40
    static let saturateAmbient: Double = 1.1

    static let shadowLiftOffset: CGFloat = 22
    static let shadowLiftBlur: CGFloat = 40
    static let focusScale: CGFloat = 1.08
    static let cardFocusScale: CGFloat = 1.04
    static let focusGapWidth: CGFloat = 3
    static let focusRingWidth: CGFloat = 4
    static let consoleFrameRowGap = tileHeight * (focusScale - 1) / 2
        + (focusGapWidth + focusRingWidth) * focusScale + Space.n3 * 2

    static let collageBlur: CGFloat = 5
    static let collageZoom: CGFloat = 1.08
    static let collageZoomSeconds: Double = 45

    static let longTitleCharacters = 30

    static func tileWidth(for aspect: CGFloat) -> CGFloat {
        tileHeight * aspect
    }
}

enum Ambient {
    static let strengthDark: Double = 0.86
    static let strengthLight: Double = 0.46
    static let heroBleed: Double = 0.15
    static let rowsBleed: Double = 0.25
}

enum Clamp {
    static let heroTitle = 2
    static let tileTitle = 5
    static let messageTitle = 3
    static let bigTileTitle = 6
}
