//
//  Trade.swift
//  EasyCrypto
//

import Foundation
import SwiftData

@Model
final class Trade {
    #Unique<Trade>([\.binanceTradeId, \.symbol])

    var binanceTradeId: Int64
    var symbol: String
    var asset: String
    var price: Double
    var quantity: Double
    var quoteQuantity: Double
    var commission: Double
    var commissionAsset: String
    var timestamp: Date
    var isBuyer: Bool
    var orderId: Int64

    init(
        binanceTradeId: Int64,
        symbol: String,
        asset: String,
        price: Double,
        quantity: Double,
        quoteQuantity: Double,
        commission: Double,
        commissionAsset: String,
        timestamp: Date,
        isBuyer: Bool,
        orderId: Int64
    ) {
        self.binanceTradeId = binanceTradeId
        self.symbol = symbol
        self.asset = asset
        self.price = price
        self.quantity = quantity
        self.quoteQuantity = quoteQuantity
        self.commission = commission
        self.commissionAsset = commissionAsset
        self.timestamp = timestamp
        self.isBuyer = isBuyer
        self.orderId = orderId
    }
}
