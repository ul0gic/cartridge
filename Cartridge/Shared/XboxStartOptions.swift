public enum XboxStartOption: String, Sendable {
    case bootROMPath = "xbox.bootROMPath"
    case flashPath = "xbox.flashPath"
    case eepromPath = "xbox.eepromPath"
    case baseDrivePath = "xbox.baseDrivePath"
    case gameDrivePath = "xbox.gameDrivePath"
    case configDirectory = "xbox.configDirectory"
    case boot = "xbox.boot"
}

public enum XboxBootMode: String, Sendable {
    case fresh
    case restore
}
