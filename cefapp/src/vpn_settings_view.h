#ifndef VPN_SETTINGS_VIEW_H
#define VPN_SETTINGS_VIEW_H

#import <Cocoa/Cocoa.h>

/// The VPN settings pane.
///
/// On Android this pane owns a full WireGuard tunnel (VpnService). On macOS the
/// app cannot create a tunnel without a signed system extension, so this pane
/// does everything that is still possible — import, validate, store in the
/// Keychain, export, and show reachability — and states the limitation plainly
/// instead of hiding it. See `docs/plan/v1.9.0-parity.md` §0.1 for the measured
/// evidence.
@interface VpnSettingsView : NSView
- (instancetype)initWithFrame:(NSRect)frame;
/// Rebuilds the profile list and status from the stores.
- (void)reload;
@end

#endif  // VPN_SETTINGS_VIEW_H
