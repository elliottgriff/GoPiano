//
//  SampleMap.swift
//  GoPiano
//
//  GENERATED - do not edit by hand. Run Tools/build-samplemap.py instead.
//
//  `frequency` is each sample's real measured pitch, not the textbook pitch of
//  its root note. The recordings run slightly sharp or flat and vary a little,
//  and handing the sampler the true frequency is what lets it retune each one
//  to concert pitch. See Tools/README.md.
//

struct SampleMap {
    struct Entry {
        let root: Int
        let frequency: Float
        let file: String
    }

    // Each sorted by root note, which `Conductor` relies on when it derives
    // key ranges.

    static let piano: [Entry] = [
        Entry(root: 21, frequency: 27.7, file: "piano_021.wav"),
        Entry(root: 22, frequency: 29.33, file: "piano_022.wav"),
        Entry(root: 23, frequency: 31.1, file: "piano_023.wav"),
        Entry(root: 24, frequency: 33.0, file: "piano_024.wav"),
        Entry(root: 25, frequency: 34.92, file: "piano_025.wav"),
        Entry(root: 26, frequency: 37.08, file: "piano_026.wav"),
        Entry(root: 27, frequency: 39.25, file: "piano_027.wav"),
        Entry(root: 28, frequency: 41.62, file: "piano_028.wav"),
        Entry(root: 29, frequency: 44.1, file: "piano_029.wav"),
        Entry(root: 30, frequency: 46.63, file: "piano_030.wav"),
        Entry(root: 31, frequency: 49.47, file: "piano_031.wav"),
        Entry(root: 32, frequency: 52.33, file: "piano_032.wav"),
        Entry(root: 33, frequency: 55.4, file: "piano_033.wav"),
        Entry(root: 34, frequency: 58.67, file: "piano_034.wav"),
        Entry(root: 35, frequency: 62.2, file: "piano_035.wav"),
        Entry(root: 36, frequency: 65.94, file: "piano_036.wav"),
        Entry(root: 37, frequency: 69.94, file: "piano_037.wav"),
        Entry(root: 38, frequency: 74.0, file: "piano_038.wav"),
        Entry(root: 39, frequency: 78.6, file: "piano_039.wav"),
        Entry(root: 40, frequency: 83.25, file: "piano_040.wav"),
        Entry(root: 41, frequency: 88.15, file: "piano_041.wav"),
        Entry(root: 42, frequency: 93.45, file: "piano_042.wav"),
        Entry(root: 43, frequency: 98.9, file: "piano_043.wav"),
        Entry(root: 44, frequency: 104.92, file: "piano_044.wav"),
        Entry(root: 45, frequency: 111.04, file: "piano_045.wav"),
        Entry(root: 46, frequency: 117.54, file: "piano_046.wav"),
        Entry(root: 47, frequency: 124.32, file: "piano_047.wav"),
        Entry(root: 48, frequency: 131.68, file: "piano_048.wav"),
        Entry(root: 49, frequency: 139.66, file: "piano_049.wav"),
        Entry(root: 50, frequency: 148.13, file: "piano_050.wav"),
        Entry(root: 51, frequency: 156.61, file: "piano_051.wav"),
        Entry(root: 52, frequency: 166.4, file: "piano_052.wav"),
        Entry(root: 53, frequency: 176.1, file: "piano_053.wav"),
        Entry(root: 54, frequency: 186.4, file: "piano_054.wav"),
        Entry(root: 55, frequency: 197.94, file: "piano_055.wav"),
        Entry(root: 56, frequency: 209.26, file: "piano_056.wav"),
        Entry(root: 57, frequency: 221.78, file: "piano_057.wav"),
        Entry(root: 58, frequency: 234.77, file: "piano_058.wav"),
        Entry(root: 59, frequency: 248.31, file: "piano_059.wav"),
        Entry(root: 60, frequency: 263.01, file: "piano_060.wav"),
        Entry(root: 61, frequency: 278.54, file: "piano_061.wav"),
        Entry(root: 62, frequency: 295.38, file: "piano_062.wav"),
        Entry(root: 63, frequency: 313.13, file: "piano_063.wav"),
        Entry(root: 64, frequency: 331.03, file: "piano_064.wav"),
        Entry(root: 65, frequency: 351.71, file: "piano_065.wav"),
        Entry(root: 66, frequency: 372.21, file: "piano_066.wav"),
        Entry(root: 67, frequency: 393.85, file: "piano_067.wav"),
        Entry(root: 68, frequency: 417.22, file: "piano_068.wav"),
        Entry(root: 69, frequency: 441.52, file: "piano_069.wav"),
        Entry(root: 70, frequency: 468.0, file: "piano_070.wav"),
        Entry(root: 71, frequency: 495.45, file: "piano_071.wav"),
        Entry(root: 72, frequency: 524.9, file: "piano_072.wav"),
        Entry(root: 73, frequency: 556.83, file: "piano_073.wav"),
        Entry(root: 74, frequency: 588.88, file: "piano_074.wav"),
        Entry(root: 75, frequency: 628.0, file: "piano_075.wav"),
        Entry(root: 76, frequency: 663.82, file: "piano_076.wav"),
        Entry(root: 77, frequency: 703.46, file: "piano_077.wav"),
        Entry(root: 78, frequency: 745.68, file: "piano_078.wav"),
        Entry(root: 79, frequency: 790.8, file: "piano_079.wav"),
        Entry(root: 81, frequency: 882.91, file: "piano_081.wav"),
        Entry(root: 82, frequency: 931.47, file: "piano_082.wav"),
        Entry(root: 83, frequency: 987.55, file: "piano_083.wav"),
        Entry(root: 84, frequency: 1044.75, file: "piano_084.wav"),
    ]

    static let electricPiano: [Entry] = [
        Entry(root: 33, frequency: 55.13, file: "epiano_033.wav"),
        Entry(root: 36, frequency: 65.69, file: "epiano_036.wav"),
        Entry(root: 41, frequency: 87.62, file: "epiano_041.wav"),
        Entry(root: 47, frequency: 124.0, file: "epiano_047.wav"),
        Entry(root: 52, frequency: 165.24, file: "epiano_052.wav"),
        Entry(root: 56, frequency: 208.95, file: "epiano_056.wav"),
        Entry(root: 61, frequency: 277.26, file: "epiano_061.wav"),
        Entry(root: 68, frequency: 415.1, file: "epiano_068.wav"),
        Entry(root: 73, frequency: 553.69, file: "epiano_073.wav"),
        Entry(root: 79, frequency: 786.69, file: "epiano_079.wav"),
        Entry(root: 85, frequency: 1107.64, file: "epiano_085.wav"),
        Entry(root: 92, frequency: 1664.86, file: "epiano_092.wav"),
    ]

    static let guitar: [Entry] = [
        Entry(root: 40, frequency: 82.65, file: "guitar_040.wav"),
        Entry(root: 41, frequency: 87.56, file: "guitar_041.wav"),
        Entry(root: 42, frequency: 92.69, file: "guitar_042.wav"),
        Entry(root: 43, frequency: 98.91, file: "guitar_043.wav"),
        Entry(root: 44, frequency: 104.48, file: "guitar_044.wav"),
        Entry(root: 45, frequency: 110.2, file: "guitar_045.wav"),
        Entry(root: 46, frequency: 116.96, file: "guitar_046.wav"),
        Entry(root: 47, frequency: 123.91, file: "guitar_047.wav"),
        Entry(root: 48, frequency: 131.12, file: "guitar_048.wav"),
        Entry(root: 49, frequency: 138.83, file: "guitar_049.wav"),
        Entry(root: 50, frequency: 147.18, file: "guitar_050.wav"),
        Entry(root: 51, frequency: 155.89, file: "guitar_051.wav"),
        Entry(root: 52, frequency: 164.88, file: "guitar_052.wav"),
        Entry(root: 53, frequency: 174.67, file: "guitar_053.wav"),
        Entry(root: 54, frequency: 185.0, file: "guitar_054.wav"),
        Entry(root: 55, frequency: 196.88, file: "guitar_055.wav"),
        Entry(root: 56, frequency: 208.78, file: "guitar_056.wav"),
        Entry(root: 57, frequency: 221.13, file: "guitar_057.wav"),
        Entry(root: 58, frequency: 234.17, file: "guitar_058.wav"),
        Entry(root: 59, frequency: 247.93, file: "guitar_059.wav"),
        Entry(root: 60, frequency: 264.14, file: "guitar_060.wav"),
        Entry(root: 61, frequency: 278.7, file: "guitar_061.wav"),
        Entry(root: 62, frequency: 295.34, file: "guitar_062.wav"),
        Entry(root: 63, frequency: 312.61, file: "guitar_063.wav"),
        Entry(root: 64, frequency: 330.56, file: "guitar_064.wav"),
        Entry(root: 65, frequency: 351.19, file: "guitar_065.wav"),
        Entry(root: 66, frequency: 371.37, file: "guitar_066.wav"),
        Entry(root: 67, frequency: 393.6, file: "guitar_067.wav"),
        Entry(root: 68, frequency: 416.43, file: "guitar_068.wav"),
        Entry(root: 69, frequency: 440.62, file: "guitar_069.wav"),
        Entry(root: 70, frequency: 466.36, file: "guitar_070.wav"),
        Entry(root: 71, frequency: 494.62, file: "guitar_071.wav"),
        Entry(root: 72, frequency: 523.54, file: "guitar_072.wav"),
        Entry(root: 73, frequency: 554.52, file: "guitar_073.wav"),
        Entry(root: 74, frequency: 587.74, file: "guitar_074.wav"),
        Entry(root: 75, frequency: 623.96, file: "guitar_075.wav"),
        Entry(root: 76, frequency: 661.66, file: "guitar_076.wav"),
        Entry(root: 77, frequency: 697.74, file: "guitar_077.wav"),
        Entry(root: 78, frequency: 738.64, file: "guitar_078.wav"),
        Entry(root: 79, frequency: 783.32, file: "guitar_079.wav"),
        Entry(root: 80, frequency: 829.59, file: "guitar_080.wav"),
        Entry(root: 81, frequency: 880.24, file: "guitar_081.wav"),
        Entry(root: 82, frequency: 930.97, file: "guitar_082.wav"),
        Entry(root: 83, frequency: 990.65, file: "guitar_083.wav"),
        Entry(root: 84, frequency: 1043.25, file: "guitar_084.wav"),
    ]

    static let lowestSampledNote = 21
    static let highestSampledNote = 84
}
