struct DiscControl {
    let callbacks: DiskControlCallbacks

    func setDisc(index: Int) throws(CoreHostFailure) {
        guard let setEjectState = callbacks.setEjectState,
              let setImageIndex = callbacks.setImageIndex,
              let getNumImages = callbacks.getNumImages
        else {
            throw CoreHostFailure(code: .noDiskControl, message: "core registered no disk control interface")
        }
        let count = cartridge_call_get_num_images(getNumImages)
        guard index >= 0, index < Int(count) else {
            throw CoreHostFailure(code: .invalidDiscIndex, message: "disc index \(index) of \(count)")
        }
        guard cartridge_call_set_eject_state(setEjectState, true) else {
            throw CoreHostFailure(code: .noDiskControl, message: "core refused to eject")
        }
        let switched = cartridge_call_set_image_index(setImageIndex, UInt32(index))
        let closed = cartridge_call_set_eject_state(setEjectState, false)
        guard switched else {
            throw CoreHostFailure(code: .invalidDiscIndex, message: "core refused disc index \(index)")
        }
        guard closed else {
            throw CoreHostFailure(code: .noDiskControl, message: "core refused to close the tray")
        }
    }
}
