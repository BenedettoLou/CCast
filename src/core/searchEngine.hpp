#pragma once
#include <vector>
#include "appDetail.hpp"

class SearchEngine{
  
  public: 
    void indexApplications();
    // collection of appDetail s
    std::vector<AppDetail> query();
  private: 
    std::vector<AppDetail> _database;

};
