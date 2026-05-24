# Figma Token → Swift Token Map

Mapping conventions from Figma token paths to Swift property names.

## Naming Convention

| Figma Path Segment | Swift Convention |
|---|---|
| `colour/background/...` | `bg...` |
| `colour/text/...` | `text...` |
| `colour/icon/...` | `icon...` |
| `colour/border/...` | `border...` |
| `colour/brand/primary/...` | `DSColor.Brand.Primary.xxx` |
| `colour/brand/neutral/...` | `DSColor.Brand.Neutral.xxx` |
| `colour/functional/...` | `DSColor.Global.Functional.xxx` |
| `colour/skywards/...` | `DSColor.Global.Skywards.xxx` |
| `spacing/app/Npx` | `.dsSpacingN` (CGFloat extension) |
| `rounding/app/small` | `DSRounding.small` |
| `rounding/app/regular` | `DSRounding.regular` |
| `rounding/app/medium` | `DSRounding.medium` |
| `rounding/app/large` | `DSRounding.large` |
| `rounding/app/full` | `DSRounding.full` |
| `shadow/app/raised/small` | `DSShadow.raisedSmall` |
| `shadow/app/raised/medium` | `DSShadow.raisedMedium` |
| `shadow/app/raised/large` | `DSShadow.raisedLarge` |
| `shadow/app/overlay` | `DSShadow.overlay` |
| `type/app/display/numbers/large` | `Font.dsDisplayLarge` |
| `type/app/display/numbers/regular` | `Font.dsDisplayRegular` |
| `type/app/heading/1` | `Font.dsHeading1` |
| `type/app/heading/2` | `Font.dsHeading2` |
| `type/app/heading/3` | `Font.dsHeading3` |
| `type/app/heading/4` | `Font.dsHeading4` |
| `type/app/heading/5` | `Font.dsHeading5` |
| `type/app/body/base` | `Font.dsBodyBase` |
| `type/app/body/small` | `Font.dsBodySmall` |
| `type/app/body/micro` | `Font.dsBodyMicro` |
| `type/app/action/button` | `Font.dsCta` |
| `type/app/action/hyperlink/base` | `Font.dsHyperlinkBase` |
| `type/app/action/hyperlink/small` | `Font.dsHyperlinkSmall` |
| `type/app/caption-overline/caption` | `Font.dsCaption` |
| `type/app/caption-overline/overline` | `Font.dsOverline` |

## Semantic Color Token Examples

### Background Tokens
| Figma Token | Swift Property |
|---|---|
| `colour/background/action/primary/enabled` | `.bgActionPrimaryEnabled` |
| `colour/background/action/primary/tapped` | `.bgActionPrimaryTapped` |
| `colour/background/action/primary/disabled` | `.bgActionPrimaryDisabled` |
| `colour/background/action/primary/pending` | `.bgActionPrimaryPending` |
| `colour/background/action/secondary/enabled` | `.bgActionSecondaryEnabled` |
| `colour/background/container/surface/bright` | `.bgContainerSurfaceBright` |
| `colour/background/container/surface/lower` | `.bgContainerSurfaceLower` |
| `colour/background/badge/neutral` | `.bgBadgeNeutral` |
| `colour/background/badge/information` | `.bgBadgeInformation` |
| `colour/background/badge/positive` | `.bgBadgePositive` |
| `colour/background/badge/warning-pending` | `.bgBadgeWarningPending` |
| `colour/background/badge/negative` | `.bgBadgeNegative` |
| `colour/background/badge/skeleton` | `.bgBadgeSkeleton` |
| `colour/background/skeleton` | `.bgSkeleton` |

### Text Tokens
| Figma Token | Swift Property |
|---|---|
| `colour/text/action/primary/enabled` | `.textActionPrimaryEnabled` |
| `colour/text/action/primary/pressed` | `.textActionPrimaryPressed` |
| `colour/text/action/primary/disabled` | `.textActionPrimaryDisabled` |
| `colour/text/general/copy` | `.textGeneralCopy` |
| `colour/text/badge/neutral` | `.textBadgeNeutral` |
| `colour/text/badge/information` | `.textBadgeInformation` |
| `colour/text/badge/positive` | `.textBadgePositive` |
| `colour/text/badge/warning-pending` | `.textBadgeWarningPending` |
| `colour/text/badge/negative` | `.textBadgeNegative` |

### Icon Tokens
| Figma Token | Swift Property |
|---|---|
| `colour/icon/general/enabled` | `.iconGeneralEnabled` |
| `colour/icon/action/primary/enabled` | `.iconActionPrimaryEnabled` |
| `colour/icon/action/secondary/enabled` | `.iconActionSecondaryEnabled` |

## Spacing Scale

| Figma Token | Swift | Value |
|---|---|---|
| `spacing/app/2px` | `.dsSpacing2` | 2 |
| `spacing/app/4px` | `.dsSpacing4` | 4 |
| `spacing/app/6px` | `.dsSpacing6` | 6 |
| `spacing/app/8px` | `.dsSpacing8` | 8 |
| `spacing/app/12px` | `.dsSpacing12` | 12 |
| `spacing/app/16px` | `.dsSpacing16` | 16 |
| `spacing/app/24px` | `.dsSpacing24` | 24 |
| `spacing/app/32px` | `.dsSpacing32` | 32 |
| `spacing/app/40px` | `.dsSpacing40` | 40 |
| `spacing/app/48px` | `.dsSpacing48` | 48 |
| `spacing/app/56px` | `.dsSpacing56` | 56 |
| `spacing/app/64px` | `.dsSpacing64` | 64 |
| `spacing/app/72px` | `.dsSpacing72` | 72 |
| `spacing/app/80px` | `.dsSpacing80` | 80 |
| `spacing/app/96px` | `.dsSpacing96` | 96 |

## Rounding Scale

| Figma Token | Swift | Value |
|---|---|---|
| `rounding/app/small` | `.small` | 4px |
| `rounding/app/regular` | `.regular` | 8px |
| `rounding/app/medium` | `.medium` | 12px |
| `rounding/app/large` | `.large` | 16px |
| `rounding/app/full` | `.full` | ∞ |

## Component Name Mapping

| Figma Component | Swift Component | Category Folder |
|---|---|---|
| Button | DSBasicButton | Button/Basic/ |
| Action Button | DSActionButton | Button/ActionButton/ |
| Card / Image Card | DSImageCard | Card/ |
| Badge | DSBadge | Badge/ |
| Banner / Hero Banner | DSTripHeroBanner | HeroBanner/ |
| Toast | DSToast | ToastMessage/ |
| Notification | DSNotificationMenu | Notification/ |
| Tab | DSBasicTab | Tab/ |
| Chip | DSChip | Chip/ |
| Bottom Sheet | DSBottomSheet | BottomSheet/ |
| Drawer | DSDrawer | Drawer/ |
| Form | DSForm | Form/ |
| Lists | DSListItem | Lists/ |
| Navigation | DSNavigation | Navigation/ |
| Pop Up | DSPopUp | PopUp/ |
| Progression Indicator | DSProgressionIndicator | ProgressionIndicator/ |
| Section Control | DSSectionControl | SectionControl/ |
| Carousel | DSCarousel | Carousel/ |
| Container | DSContainer | Container/ |
| Country Selector | DSCountrySelector | CountrySelector/ |

## Figma Reference URLs

- [Core Components](https://www.figma.com/design/WtUfdvuiW8ZDDF66JdTYXx/App-%7C-Core-Components?node-id=149-19943)
- [Foundations](https://www.figma.com/design/iHWKFqO4RT0dbIRIX8xCdn/App-%7C-Foundations?node-id=1-4159&m=dev)
