#import <Foundation/Foundation.h>

/// stdio ↔ Unix-socket shim for MCP clients.
///
/// The Claude desktop app spawns `VisualCoach --mcp-relay` and speaks
/// newline-delimited JSON-RPC over stdio; the relay connects to the running
/// menu-bar app's MCP socket (launching the app via `open` if needed) and
/// pumps bytes both ways. Returns a process exit code.
int VCRunMCPRelay(void);
