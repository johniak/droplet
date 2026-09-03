/// Landscape phones and tablets: enough width to put the search field into
/// the header row instead of spending a full row of a short screen on it.
/// Decided from the actual layout constraints (LayoutBuilder), not from
/// MediaQuery, so a screen embedded in a narrower parent still behaves.
const double kWideBreakpoint = 600;

bool isWideWidth(double width) => width >= kWideBreakpoint;

/// Width of the inline search field in a wide header.
const double kInlineSearchWidth = 360;

/// Every tile is square, whatever the art: Switch covers are square eShop
/// icons and portrait boxarts sit on their blurred backdrop. One shape keeps
/// shelves and grids even.
const double kCoverAspectRatio = 1;

double coverAspectRatio(String systemCode) => kCoverAspectRatio;

/// Height-to-width factor of a cover cell.
double tallestCoverFactor(Iterable<String> systemCodes) => 1 / kCoverAspectRatio;

/// Vertical space (as a fraction of the card width) the title and size text
/// take under a cover in the grid: the original 0.58 cell held a 4:3-tall cover.
const double kGridTextFactor = 1 / 0.58 - 4 / 3;
