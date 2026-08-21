"use strict";



// A map containing the URLs for the bootstrap scripts in debug.
let _scriptUrls = {
  "mapper": "stack_trace_mapper.js",
  "requireJs": "require.js"
};

// Create a TrustedTypes policy so we can attach Scripts...
let _ttPolicy;
if (window.trustedTypes) {
  _ttPolicy = trustedTypes.createPolicy("flutter-tools-bootstrap", {
    createScriptURL: (url) => {
      let scriptUrl = _scriptUrls[url];
      if (!scriptUrl) {
        console.error("Unknown Flutter Web bootstrap resource!", url);
      }
      return scriptUrl;
    }
  });
}

// Creates a TrustedScriptURL for a given `scriptName`.
// See `_scriptUrls` and `_ttPolicy` above.
function getTTScriptUrl(scriptName) {
  let defaultUrl = _scriptUrls[scriptName];
  return _ttPolicy ? _ttPolicy.createScriptURL(scriptName) : defaultUrl;
}

// Attach source mapping.
var mapperEl = document.createElement("script");
mapperEl.defer = true;
mapperEl.async = false;
mapperEl.src = getTTScriptUrl("mapper");
document.head.appendChild(mapperEl);

// Attach require JS.
var requireEl = document.createElement("script");
requireEl.defer = true;
requireEl.async = false;
requireEl.src = getTTScriptUrl("requireJs");
// This attribute tells require JS what to load as main (defined below).
requireEl.setAttribute("data-main", "main_module.bootstrap");
document.head.appendChild(requireEl);
