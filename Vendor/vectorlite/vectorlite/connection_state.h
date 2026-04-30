#pragma once

#include <string>
#include <unordered_map>

namespace vectorlite {

class VirtualTable;

class ConnectionState {
 public:
  void RegisterTable(const std::string& table_name, VirtualTable* table) {
    tables_[table_name] = table;
  }

  void UnregisterTable(const std::string& table_name, VirtualTable* table) {
    auto it = tables_.find(table_name);
    if (it != tables_.end() && it->second == table) {
      tables_.erase(it);
    }
  }

  VirtualTable* FindTable(const std::string& table_name) const {
    auto it = tables_.find(table_name);
    return it == tables_.end() ? nullptr : it->second;
  }

 private:
  std::unordered_map<std::string, VirtualTable*> tables_;
};

}  // namespace vectorlite
