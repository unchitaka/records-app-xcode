//
//  Record_CatalogApp.swift
//  Record Catalog
//
//  Created by Steven Forrester on 2026/04/18.
//

import SwiftUI
import CoreData

@main
struct Record_CatalogApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
