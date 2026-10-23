package org.jitsi.meet.sdk

/**
 * Connect fork: audio output for the app's own call controls. Lives in the
 * SDK package to reach the package-private AudioModeModule, so the choice
 * goes through Jitsi's own audio handling instead of fighting it.
 */
object ConnectAudioRoutes {
    private fun module(): AudioModeModule? =
        try {
            ReactHostHolder.getNativeModule(AudioModeModule::class.java)
        } catch (e: Throwable) {
            null
        }

    /** [route]: `speaker`, `earpiece`, `headphones` or `bluetooth`. */
    fun select(route: String) {
        val device = when (route) {
            "speaker" -> AudioModeModule.DEVICE_SPEAKER
            "earpiece" -> AudioModeModule.DEVICE_EARPIECE
            "headphones" -> AudioModeModule.DEVICE_HEADPHONES
            "bluetooth" -> AudioModeModule.DEVICE_BLUETOOTH
            else -> return
        }
        module()?.setAudioDevice(device)
    }

    fun state(): Map<String, Any?> {
        val module = module() ?: return mapOf("route" to "unknown", "available" to emptyList<String>())
        val selected = try {
            module.selectedDevice
        } catch (e: Throwable) {
            null
        }
        val available = try {
            val field = AudioModeModule::class.java.getDeclaredField("availableDevices")
            field.isAccessible = true
            (field.get(module) as? Set<*>)?.mapNotNull { it?.toString() } ?: emptyList()
        } catch (e: Throwable) {
            emptyList()
        }
        return mapOf(
            "route" to toRoute(selected),
            "available" to available.map(::toRoute).filter { it != "unknown" }
        )
    }

    private fun toRoute(device: String?): String = when (device) {
        AudioModeModule.DEVICE_SPEAKER -> "speaker"
        AudioModeModule.DEVICE_EARPIECE -> "earpiece"
        AudioModeModule.DEVICE_HEADPHONES -> "headphones"
        AudioModeModule.DEVICE_BLUETOOTH -> "bluetooth"
        else -> "unknown"
    }
}
