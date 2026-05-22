import Foundation

struct PiperVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: String

    var displayName: String {
        "\(language) - \(name) (\(quality))"
    }
}

enum PiperVoiceCatalog {
    nonisolated static let previewText = NarrationService.previewText

    nonisolated static var englishVoiceIDs: [String] {
        voices
            .filter { $0.language.hasPrefix("English") }
            .map(\.id)
    }

    nonisolated static let voices: [PiperVoice] = [
        PiperVoice(id: "en_US-lessac-medium", name: "Lessac", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-lessac-high", name: "Lessac", language: "English US", quality: "high"),
        PiperVoice(id: "en_US-lessac-low", name: "Lessac", language: "English US", quality: "low"),
        PiperVoice(id: "en_US-amy-medium", name: "Amy", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-amy-low", name: "Amy", language: "English US", quality: "low"),
        PiperVoice(id: "en_US-ryan-medium", name: "Ryan", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-ryan-high", name: "Ryan", language: "English US", quality: "high"),
        PiperVoice(id: "en_US-ryan-low", name: "Ryan", language: "English US", quality: "low"),
        PiperVoice(id: "en_US-kathleen-low", name: "Kathleen", language: "English US", quality: "low"),
        PiperVoice(id: "en_US-danny-low", name: "Danny", language: "English US", quality: "low"),
        PiperVoice(id: "en_US-libritts-high", name: "LibriTTS", language: "English US", quality: "high"),
        PiperVoice(id: "en_US-libritts_r-medium", name: "LibriTTS R", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-arctic-medium", name: "Arctic", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-bryce-medium", name: "Bryce", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-hfc_female-medium", name: "HFC Female", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-hfc_male-medium", name: "HFC Male", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-joe-medium", name: "Joe", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-john-medium", name: "John", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-kusal-medium", name: "Kusal", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-l2arctic-medium", name: "L2 Arctic", language: "English US", quality: "medium"),
        PiperVoice(id: "en_US-norman-medium", name: "Norman", language: "English US", quality: "medium"),
        PiperVoice(id: "en_GB-alan-medium", name: "Alan", language: "English UK", quality: "medium"),
        PiperVoice(id: "en_GB-alan-low", name: "Alan", language: "English UK", quality: "low"),
        PiperVoice(id: "en_GB-alba-medium", name: "Alba", language: "English UK", quality: "medium"),
        PiperVoice(id: "en_GB-aru-medium", name: "Aru", language: "English UK", quality: "medium"),
        PiperVoice(id: "en_GB-cori-high", name: "Cori", language: "English UK", quality: "high"),
        PiperVoice(id: "en_GB-cori-medium", name: "Cori", language: "English UK", quality: "medium"),
        PiperVoice(id: "en_GB-jenny_dioco-medium", name: "Jenny Dioco", language: "English UK", quality: "medium"),
        PiperVoice(id: "en_GB-northern_english_male-medium", name: "Northern English Male", language: "English UK", quality: "medium"),
        PiperVoice(id: "en_GB-semaine-medium", name: "Semaine", language: "English UK", quality: "medium"),
        PiperVoice(id: "en_GB-southern_english_female-low", name: "Southern English Female", language: "English UK", quality: "low"),
        PiperVoice(id: "en_GB-vctk-medium", name: "VCTK", language: "English UK", quality: "medium"),
        PiperVoice(id: "de_DE-thorsten-medium", name: "Thorsten", language: "German", quality: "medium"),
        PiperVoice(id: "de_DE-thorsten-high", name: "Thorsten", language: "German", quality: "high"),
        PiperVoice(id: "de_DE-thorsten-low", name: "Thorsten", language: "German", quality: "low"),
        PiperVoice(id: "de_DE-thorsten_emotional-medium", name: "Thorsten Emotional", language: "German", quality: "medium"),
        PiperVoice(id: "de_DE-kerstin-low", name: "Kerstin", language: "German", quality: "low"),
        PiperVoice(id: "de_DE-mls-medium", name: "MLS", language: "German", quality: "medium"),
        PiperVoice(id: "es_ES-davefx-medium", name: "DaveFX", language: "Spanish Spain", quality: "medium"),
        PiperVoice(id: "es_ES-sharvard-medium", name: "Sharvard", language: "Spanish Spain", quality: "medium"),
        PiperVoice(id: "es_ES-mls_10246-low", name: "MLS 10246", language: "Spanish Spain", quality: "low"),
        PiperVoice(id: "es_ES-mls_9972-low", name: "MLS 9972", language: "Spanish Spain", quality: "low"),
        PiperVoice(id: "es_MX-ald-medium", name: "ALD", language: "Spanish Mexico", quality: "medium"),
        PiperVoice(id: "fr_FR-siwis-medium", name: "Siwis", language: "French", quality: "medium"),
        PiperVoice(id: "fr_FR-siwis-low", name: "Siwis", language: "French", quality: "low"),
        PiperVoice(id: "fr_FR-tom-medium", name: "Tom", language: "French", quality: "medium"),
        PiperVoice(id: "fr_FR-upmc-medium", name: "UPMC", language: "French", quality: "medium"),
        PiperVoice(id: "fr_FR-gilles-low", name: "Gilles", language: "French", quality: "low"),
        PiperVoice(id: "fr_FR-mls-medium", name: "MLS", language: "French", quality: "medium"),
        PiperVoice(id: "it_IT-paola-medium", name: "Paola", language: "Italian", quality: "medium"),
        PiperVoice(id: "it_IT-riccardo-x_low", name: "Riccardo", language: "Italian", quality: "x-low"),
        PiperVoice(id: "nl_NL-mls-medium", name: "MLS", language: "Dutch", quality: "medium"),
        PiperVoice(id: "nl_BE-nathalie-medium", name: "Nathalie", language: "Dutch Belgium", quality: "medium"),
        PiperVoice(id: "nl_BE-rdh-medium", name: "RDH", language: "Dutch Belgium", quality: "medium"),
        PiperVoice(id: "pt_BR-faber-medium", name: "Faber", language: "Portuguese Brazil", quality: "medium"),
        PiperVoice(id: "pt_BR-edresson-low", name: "Edresson", language: "Portuguese Brazil", quality: "low"),
        PiperVoice(id: "pt_PT-tugao-medium", name: "Tugao", language: "Portuguese Portugal", quality: "medium"),
        PiperVoice(id: "pl_PL-darkman-medium", name: "Darkman", language: "Polish", quality: "medium"),
        PiperVoice(id: "pl_PL-gosia-medium", name: "Gosia", language: "Polish", quality: "medium"),
        PiperVoice(id: "pl_PL-mc_speech-medium", name: "MC Speech", language: "Polish", quality: "medium"),
        PiperVoice(id: "sv_SE-nst-medium", name: "NST", language: "Swedish", quality: "medium"),
        PiperVoice(id: "da_DK-talesyntese-medium", name: "Talesyntese", language: "Danish", quality: "medium"),
        PiperVoice(id: "fi_FI-harri-medium", name: "Harri", language: "Finnish", quality: "medium"),
        PiperVoice(id: "no_NO-talesyntese-medium", name: "Talesyntese", language: "Norwegian", quality: "medium"),
        PiperVoice(id: "cs_CZ-jirka-medium", name: "Jirka", language: "Czech", quality: "medium"),
        PiperVoice(id: "hu_HU-anna-medium", name: "Anna", language: "Hungarian", quality: "medium"),
        PiperVoice(id: "hu_HU-berta-medium", name: "Berta", language: "Hungarian", quality: "medium"),
        PiperVoice(id: "hu_HU-imre-medium", name: "Imre", language: "Hungarian", quality: "medium"),
        PiperVoice(id: "ru_RU-irina-medium", name: "Irina", language: "Russian", quality: "medium"),
        PiperVoice(id: "ru_RU-denis-medium", name: "Denis", language: "Russian", quality: "medium"),
        PiperVoice(id: "ru_RU-dmitri-medium", name: "Dmitri", language: "Russian", quality: "medium"),
        PiperVoice(id: "ru_RU-ruslan-medium", name: "Ruslan", language: "Russian", quality: "medium"),
        PiperVoice(id: "uk_UA-ukrainian_tts-medium", name: "Ukrainian TTS", language: "Ukrainian", quality: "medium"),
        PiperVoice(id: "tr_TR-dfki-medium", name: "DFKI", language: "Turkish", quality: "medium"),
        PiperVoice(id: "tr_TR-fahrettin-medium", name: "Fahrettin", language: "Turkish", quality: "medium"),
        PiperVoice(id: "tr_TR-fettah-medium", name: "Fettah", language: "Turkish", quality: "medium"),
        PiperVoice(id: "zh_CN-huayan-medium", name: "Huayan", language: "Chinese", quality: "medium"),
        PiperVoice(id: "vi_VN-vais1000-medium", name: "VAIS1000", language: "Vietnamese", quality: "medium"),
        PiperVoice(id: "ar_JO-kareem-medium", name: "Kareem", language: "Arabic Jordan", quality: "medium")
    ]
}

enum NarrationVoiceCatalog {
    nonisolated static func voices(for engine: NarrationEngine) -> [PiperVoice] {
        switch engine {
        case .piper:
            PiperVoiceCatalog.voices
        case .kokoro:
            [
                PiperVoice(id: "af_heart", name: "Heart", language: "English US", quality: "premium"),
                PiperVoice(id: "af_bella", name: "Bella", language: "English US", quality: "premium"),
                PiperVoice(id: "af_nicole", name: "Nicole", language: "English US", quality: "premium"),
                PiperVoice(id: "af_sarah", name: "Sarah", language: "English US", quality: "premium"),
                PiperVoice(id: "am_adam", name: "Adam", language: "English US", quality: "premium"),
                PiperVoice(id: "am_michael", name: "Michael", language: "English US", quality: "premium"),
                PiperVoice(id: "bf_emma", name: "Emma", language: "English UK", quality: "premium"),
                PiperVoice(id: "bf_isabella", name: "Isabella", language: "English UK", quality: "premium"),
                PiperVoice(id: "bm_george", name: "George", language: "English UK", quality: "premium"),
                PiperVoice(id: "bm_lewis", name: "Lewis", language: "English UK", quality: "premium")
            ]
        }
    }
}
