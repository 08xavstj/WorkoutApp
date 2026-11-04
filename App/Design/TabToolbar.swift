import SwiftUI

/// The profile button every tab's navigation bar carries (trailing), opening
/// Settings as a sheet from the root (`AppRouter.showSettings`).
///
/// Apply it to a tab's root view, inside its `NavigationStack`:
/// `.tabToolbar()`. One place to open Settings from any tab, in the system
/// navigation bar so it gets Liquid Glass (docs/research/ux-audit.md 4.1 rule 3:
/// HIG *Toolbars*; WWDC25 session 356).
struct TabToolbar: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "person.crop.circle") {
                        router.showSettings = true
                    }
                    .accessibilityHint("Opens your profile, goals and settings.")
                }
            }
    }
}

extension View {
    /// Adds the trailing profile/Settings button to a tab's navigation bar.
    func tabToolbar() -> some View {
        modifier(TabToolbar())
    }
}
