/// Landscape phones and tablets: enough width to put the search field into
/// the header row instead of spending a full row of a short screen on it.
/// Decided from the actual layout constraints (LayoutBuilder), not from
/// MediaQuery, so a screen embedded in a narrower parent still behaves.
const double kWideBreakpoint = 600;

bool isWideWidth(double width) => width >= kWideBreakpoint;

/// Width of the inline search field in a wide header.
const double kInlineSearchWidth = 360;
