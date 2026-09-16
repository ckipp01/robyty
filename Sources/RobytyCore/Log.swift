import os

public enum Log {
    public static let app = Logger(subsystem: "com.chriskipp.robyty", category: "app")
    public static let store = Logger(subsystem: "com.chriskipp.robyty", category: "store")
}
