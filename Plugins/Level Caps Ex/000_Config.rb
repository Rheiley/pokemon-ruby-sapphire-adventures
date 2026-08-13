module LevelCapsEX
  #=============================================================================
  # [SC] Level Caps Ex - Configuration
  # Shattered Crowns fork of Level Caps EX v2.3.2
  #=============================================================================

  # Set this to the Game Variable which controls the value of the
  # level cap
  LEVEL_CAP_VARIABLE      = 198

  # Set this to the Game Variable which controls the mode of the
  # level cap. The 3 modes are:
  #   1 (Hard Cap) - The Pokemon cannot level up/gain experience 
  #   past the level cap.
  #   2 (EXP Cap) - The Pokemon will gain reduced EXP when it
  #   crosses the level cap.
  #   3 (Obedience Cap)  - The Pokemon will disobey the player
  #   when it crosses the level cap.
  LEVEL_CAP_MODE_VARIABLE = 199

  # Set this to the default mode of the Level Cap
  DEFAULT_LEVEL_CAP_MODE  = 1

  # Set this to the Game Switch which, when ON, disables level cap for enemy trainers
  LEVEL_CAP_BYPASS_SWITCH = 200

  # Set this to true if any changes to the Level Cap/Level Cap mode
  # should be printed to the console (only in debug builds).
  LOG_LEVEL_CAP_CHANGES   = true

  #---------------------------------------------------------------------------
  # Badge-Based Auto Level Cap
  #---------------------------------------------------------------------------
  # When BADGE_AUTO_CAP is true, the level cap automatically updates
  # whenever the player earns a new badge. The BADGE_LEVEL_CAPS hash
  # maps badge count → new level cap. Set to false to disable.
  BADGE_AUTO_CAP = true

  BADGE_LEVEL_CAPS = {
    0 => 15,   # Start of game
    1 => 20,   # After Badge 1
    2 => 25,   # After Badge 2
    3 => 30,   # After Badge 3
    4 => 35,   # After Badge 4
    5 => 45,   # After Badge 5
    6 => 55,   # After Badge 6
    7 => 65,   # After Badge 7
    8 => 75,   # After Badge 8 (Champion run)
    9 => 100   # Post-game (set via event or 9th "badge" flag)
  }

  #---------------------------------------------------------------------------
  # Soft Cap Scaling
  #---------------------------------------------------------------------------
  # When true, the soft cap (mode 2) uses a smooth EXP reduction curve
  # instead of the flat 1/10 reduction. The multiplier halves for each level
  # from the cap onward, with a 1% floor:
  #   at cap = 50%, 1 over = 25%, 2 over = 12.5%, 5 over ≈ 1.6%, then 1%.
  # When false, uses the original flat 1/10 reduction.
  SOFT_CAP_SCALED = true

  #---------------------------------------------------------------------------
  # Shared-EXP Respect for Level Cap
  #---------------------------------------------------------------------------
  # When true, Pokemon at or above the level cap won't receive passive EXP
  # from Exp Share or Exp All — even in soft cap (mode 2) or obedience cap
  # (mode 3), where they would otherwise still gain (reduced or full) EXP via
  # the share. Direct battle participation is unaffected.
  # Hard cap (mode 1) always blocks all EXP for at-cap Pokemon regardless.
  SHARED_EXP_RESPECTS_CAP = true

  #---------------------------------------------------------------------------
  # Items vs. the Soft / EXP Cap
  #---------------------------------------------------------------------------
  # In EXP Cap mode (2), battle EXP may carry a Pokemon PAST the cap (heavily
  # reduced). This controls whether EXP *items* do the same:
  #   true  — Rare Candy and EXP Candies stop AT the cap (the item is refused
  #           once the cap is reached), matching a Hard Cap. [default]
  #   false — Rare Candy and EXP Candies may also carry a Pokemon past the cap,
  #           consistent with battle EXP in this mode.
  # Hard Cap (1) always stops items at the cap, regardless of this setting.
  ITEMS_RESPECT_SOFT_CAP = true

  #---------------------------------------------------------------------------
  # EXP Storage (Piggy Bank)
  #---------------------------------------------------------------------------
  # When true and the hard cap is active, EXP that would otherwise be lost is
  # banked per-Pokemon (keyed by personalID) and awarded automatically the
  # moment the cap rises (badge auto-cap, debug set, or an event script that
  # sets $game_variables[LEVEL_CAP_VARIABLE]). Storage lives in
  # $PokemonGlobal.level_cap_stored_exp and survives save/load — there is no
  # Game Variable to configure for it.
  EXP_STORAGE_ENABLED  = true
end
