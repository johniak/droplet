/// Landscape phones and tablets: enough width to put the search field into
/// the header row instead of spending a full row of a short screen on it.
/// Decided from the actual layout constraints (LayoutBuilder), not from
/// MediaQuery, so a screen embedded in a narrower parent still behaves.
const double kWideBreakpoint = 600;

bool isWideWidth(double width) => width >= kWideBreakpoint;

/// Width of the inline search field in a wide header.
const double kInlineSearchWidth = 360;

/// Cover aspect ratio (width / height) per system. libretro boxarts are
/// portrait; Switch covers are eShop icons, which are square.
double coverAspectRatio(String systemCode) => systemCode == 'switch' ? 1 : 3 / 4;

/// Height-to-width factor of the tallest cover among [systemCodes] — a mixed
/// shelf or grid sizes its cells for the tallest card.
double tallestCoverFactor(Iterable<String> systemCodes) {
  var factor = 0.0;
  for (final code in systemCodes) {
    final f = 1 / coverAspectRatio(code);
    if (f > factor) factor = f;
  }
  return factor == 0 ? 1 / coverAspectRatio('') : factor;
}

/// Vertical space (as a fraction of the card width) the title and size text
/// take under a cover in the grid: the old 0.58 cell held a 4:3-tall cover.
const double kGridTextFactor = 1 / 0.58 - 4 / 3;
