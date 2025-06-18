//
//  RiderSearchPushRow.swift
//  openshift-ims
//
//  Created by Phua June Jin on 25/07/2023.
//

import Eureka
import Foundation
import UIKit

protocol SearchItem {
  func matchesSearchQuery(_ query: String) -> Bool
  func matchesScope(_ scopeName: String) -> Bool
}

extension SearchItem {
  func matchesScope(_ scopeName: String) -> Bool {
    true
  }
}

class _RiderSearchSelectorViewController<Row: SelectableRowType, OptionsRow: OptionsProviderRow>: SelectorViewController<OptionsRow>, UISearchResultsUpdating, UISearchBarDelegate where Row.Cell.Value: SearchItem {
  private let allScopeTitle = "ALL"
  let searchController = UISearchController(searchResultsController: nil)
  var showAllScope = true
  var scopeTitles: [String]?
  var originalOptions = [[ListCheckRow<Row.Cell.Value>]]()
  var currentOptions = [[ListCheckRow<Row.Cell.Value>]]()
  
  init(scopeTitles: [String]?, showAllScope: Bool) {
    self.scopeTitles = scopeTitles
    self.showAllScope = showAllScope
    super.init(nibName: nil, bundle: nil)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  open override func viewDidLoad() {
    super.viewDidLoad()
    
    definesPresentationContext = true
    
    searchController.searchResultsUpdater = self
    searchController.searchBar.showsScopeBar = false
    searchController.obscuresBackgroundDuringPresentation = false
    
    if let scopes = scopeTitles {
      searchController.searchBar.scopeButtonTitles = showAllScope ? [allScopeTitle] + scopes : scopes
      searchController.searchBar.showsScopeBar = self.traitCollection.horizontalSizeClass != .compact
      searchController.searchBar.delegate = self
    }
    
    navigationItem.searchController = searchController
    navigationItem.hidesSearchBarWhenScrolling = false
  }
  
  open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    
    coordinator.animate(alongsideTransition: { (context) in
      UIView.performWithoutAnimation {
        self.searchController.isActive = false
        self.searchController.searchBar.text = nil
        self.searchController.searchBar.selectedScopeButtonIndex = 0
        self.searchController.searchBar.showsScopeBar = self.traitCollection.horizontalSizeClass != .compact
        
        self.filterOptions(searchText: "", scope: nil)
      }
    })
  }
  
  open override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
    currentOptions[section].count == 0 ? 0 : super.tableView(tableView, heightForHeaderInSection: section)
  }
  
  open override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
    currentOptions[section].count == 0 ? 0 : super.tableView(tableView, heightForFooterInSection: section)
  }
  
  open override func numberOfSections(in tableView: UITableView) -> Int {
    currentOptions.count
  }
  
  open override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    currentOptions[section].count
  }
  
  open override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let option = currentOptions[indexPath.section][indexPath.row]
    option.updateCell()
    
    return option.baseCell
  }
  
  open override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    currentOptions[indexPath.section][indexPath.row].didSelect()
  }
  
  open override func setupForm(with options: [OptionsRow.OptionsProviderType.Option]) {
    super.setupForm(with: options)
    
    for section in form.allSections {
      if let rows = section.allRows as? [ListCheckRow<Row.Cell.Value>] {
        originalOptions.append(rows)
        currentOptions = originalOptions
      }
    }
    
    tableView.reloadData()
  }
  
  func updateSearchResults(for searchController: UISearchController) {
    let sb = searchController.searchBar
    let searchText = sb.text ?? ""
    let scope = sb.scopeButtonTitles?[sb.selectedScopeButtonIndex]
    
    filterOptions(searchText: searchText, scope: scope)
  }
  
  func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
    searchBar.text = ""
  }
  
  private func filterOptions(searchText: String, scope: String?) {
    if let scope, scope != allScopeTitle {
      filterBy(scope: scope)
    } else {
      filterBy(searchText: searchText)
    }
    
    tableView.reloadData()
  }
  
  private func filterBy(searchText: String) {
    currentOptions = searchText.isEmpty ? originalOptions : originalOptions.map({
      $0.filter {
        guard let value = $0.selectableValue else { return false }
        return value.matchesSearchQuery(searchText)
      }
    })
  }
  
  private func filterBy(scope: String) {
    currentOptions = originalOptions.map({
      $0.filter { item in
        guard let value = item.selectableValue else { return false }
        return scope == allScopeTitle || value.matchesScope(scope)
      }
    })
  }
}

@MainActor
class RiderSearchSelectorViewController<OptionsRow: OptionsProviderRow>: _RiderSearchSelectorViewController<ListCheckRow<OptionsRow.OptionsProviderType.Option>, OptionsRow> where OptionsRow.OptionsProviderType.Option: SearchItem {}

@MainActor
class _RiderSearchPushRow<Cell: CellType>: SelectorRow<Cell> where Cell: BaseCell, Cell.Value: SearchItem {
  open var scopeTitles: [String]? {
    didSet {
      //MainActor.assumeIsolated {
        self.updateControllerProvider()
      //}
    }
  }
  open var showAllScope = true
  
  required init(tag: String?) {
    super.init(tag: tag)
    MainActor.assumeIsolated {
      self.updateControllerProvider()
    }
  }
  
  private func updateControllerProvider() {
    presentationMode = .show(controllerProvider: ControllerProvider.callback {
      let svc = RiderSearchSelectorViewController<SelectorRow<Cell>>(scopeTitles: self.scopeTitles, showAllScope: self.showAllScope)
      return svc
    }, onDismiss: { vc in
      Task { @MainActor in
        vc.navigationController?.popViewController(animated: true)
      }
    })
  }
}

final class RiderSearchPushRow<T: Equatable>: _RiderSearchPushRow<PushSelectorCell<T>>, RowType where T: SearchItem {
  required init(tag: String?) {
    super.init(tag: tag)
  }
}
