//
//  DbStoreError.swift
//  SQLiteStore
//
//  Created by Aikyuichi on 13/7/26.
//  Copyright (c) 2022 aikyuichi <aikyu.sama@gmail.com>
//  Use of this source code is governed by a MIT license that can be found in the LICENSE file.
//

import Foundation

public struct DbStoreError: Error, CustomStringConvertible, LocalizedError {
    public let message: String
    public let description: String
    
    public var errorDescription: String? {
        return description
    }
    
    init(message: String) {
        self.message = message
        self.description = message
    }
}
