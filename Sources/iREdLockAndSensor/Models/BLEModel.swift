//
//  BLEModel.swift
//  LockAppMiniDemo
//
//  Created by Kehong-IOS-Dev01 on 2026/6/4.
//

public enum PairStatus: String, Codable, Sendable {
    case notPair = "Not Pair"
    case paired = "Paired"
    case pairing = "Pairing"
}

public enum ConnectStatus: String, Codable, Sendable {
    case unknown = "Unknown"
    case connected = "Connected"
    case connecting = "Connecting"
    case disconnected = "Disconnected"
    case connectionFailed = "Connection Failed"
}
