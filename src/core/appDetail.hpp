/*
 *
 * App details to be searched
 *
 */

#pragma once
#include <string>

struct AppDetail { 
  std::string name;   // name shown to the user (localized if available)
  std::string path;   // absolute path of the .app bundle
};
