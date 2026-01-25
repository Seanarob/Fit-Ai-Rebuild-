import AudioToolbox

enum SoundEffects {
    static func restComplete() {
        AudioServicesPlaySystemSound(1005)
    }
}
