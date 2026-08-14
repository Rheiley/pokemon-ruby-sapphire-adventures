#===============================================================================
# [SC] Level Caps Ex - Additions (v2.7.0)
# Shattered Crowns fork of Level Caps EX v2.3.2
# Item handler overrides for Rare Candy, EXP Candies, Game Variable logging
#===============================================================================

#-------------------------------------------------------------------------------
# Rare Candy edits for Level Caps
#-------------------------------------------------------------------------------
ItemHandlers::UseOnPokemonMaximum.add(:RARECANDY, proc { |item, pkmn|
  # Calculate maximum based on level caps
  if LevelCapsEX.hard_cap? || LevelCapsEX.soft_cap?
    max_lv = LevelCapsEX.level_cap
    # Don't allow any if already at or above cap
    next 0 if pkmn.level >= max_lv
    next max_lv - pkmn.level
  else
    # No level cap active, use game maximum
    max_lv = GameData::GrowthRate.max_level
    next max_lv - pkmn.level
  end
})

ItemHandlers::UseOnPokemon.add(:RARECANDY, proc { |item, qty, pkmn, scene|
  if pkmn.shadowPokemon?
    scene.pbDisplay(_INTL("It won't have any effect."))
    next false
  elsif pkmn.level >= GameData::GrowthRate.max_level
    new_species = pkmn.check_evolution_on_level_up
    if !Settings::RARE_CANDY_USABLE_AT_MAX_LEVEL || !new_species
      scene.pbDisplay(_INTL("It won't have any effect."))
      next false
    end
    # Check for evolution
    pbFadeOutInWithMusic do
      evo = PokemonEvolutionScene.new
      evo.pbStartScreen(pkmn, new_species)
      evo.pbEvolution
      evo.pbEndScreen
      scene.pbRefresh if scene.is_a?(PokemonPartyScreen)
    end
    next true
  elsif LevelCapsEX.items_capped? && pkmn.level >= LevelCapsEX.level_cap
    # The cap blocks items in this mode: don't raise the level, but still allow
    # a pending level-up evolution (Gen 8 Rare Candy behaviour). In EXP Cap mode
    # with ITEMS_RESPECT_SOFT_CAP off this branch is skipped, so the candy falls
    # through to the level-up loop and can carry the Pokemon past the cap.
    new_species = Settings::RARE_CANDY_USABLE_AT_MAX_LEVEL ? pkmn.check_evolution_on_level_up : nil
    if !new_species
      scene.pbDisplay(_INTL("{1} refuses to eat the {2}.", pkmn.name, GameData::Item.get(item).name))
      next false
    end
    pbFadeOutInWithMusic do
      evo = PokemonEvolutionScene.new
      evo.pbStartScreen(pkmn, new_species)
      evo.pbEvolution
      evo.pbEndScreen
      scene.pbRefresh if scene.is_a?(PokemonPartyScreen)
    end
    next true
  end
  # Level up - respect level caps by leveling one at a time
  pbSEPlay("Pkmn level up")
  target_level = pkmn.level + qty
  actual_levels_gained = 0
  
  # Level up one at a time to respect level caps
  qty.times do |i|
    break if pkmn.level >= target_level
    # Stop at the cap when the active mode blocks items there (Hard Cap always;
    # EXP Cap only when ITEMS_RESPECT_SOFT_CAP). Otherwise keep leveling past it.
    break if LevelCapsEX.items_capped? && pkmn.level >= LevelCapsEX.level_cap
    
    old_level = pkmn.level
    # Use direct level assignment to trigger level cap checks
    pkmn.level = pkmn.level + 1
    pkmn.calc_stats

    actual_levels_gained += 1 if pkmn.level > old_level
    
    # Learn all moves learned at this level
    moveList = pkmn.getMoveList
    moveList.each do |m|
      next if m[0] != pkmn.level
      pbLearnMove(pkmn, m[1]) { scene.pbUpdate if scene.respond_to?(:pbUpdate) }
    end
    
    # Check for evolution at new level
    new_species = pkmn.check_evolution_on_level_up
    if new_species
      pbFadeOutInWithMusic do
        evo = PokemonEvolutionScene.new
        evo.pbStartScreen(pkmn, new_species)
        evo.pbEvolution
        evo.pbEndScreen
        scene.pbRefresh if scene.respond_to?(:pbRefresh)
      end
    end
  end
  
  # Tell the player what happened — a per-use summary for multiple candies,
  # or the familiar "grew to Lv. X" line for a single one (the manual loop
  # above bypasses pbChangeLevel, which would normally show that message).
  if actual_levels_gained > 0 && scene.respond_to?(:pbDisplay)
    if qty > 1
      scene.pbDisplay(_INTL("{1} gained {2} level(s) from {3} Rare Candies!", pkmn.name, actual_levels_gained, qty))
    else
      scene.pbDisplay(_INTL("{1} grew to Lv. {2}!", pkmn.name, pkmn.level))
    end
  end
  
  scene.pbHardRefresh
  next true
})

#-------------------------------------------------------------------------------
# EXP Candy Edits for Level Caps
#-------------------------------------------------------------------------------
ItemHandlers::UseOnPokemonMaximum.add(:EXPCANDYXS, proc { |item, pkmn|
  gain_amount = 100
  max_exp = LevelCapsEX.items_capped? ? pkmn.growth_rate.minimum_exp_for_level(LevelCapsEX.level_cap) : pkmn.growth_rate.maximum_exp
  next [((max_exp - pkmn.exp) / gain_amount.to_f).ceil, 0].max
})

ItemHandlers::UseOnPokemon.add(:EXPCANDYXS, proc { |item, qty, pkmn, scene|
  next pbGainExpFromExpCandy(pkmn, 100, qty, scene, item)
})

ItemHandlers::UseOnPokemonMaximum.add(:EXPCANDYS, proc { |item, pkmn|
  gain_amount = 800
  max_exp = LevelCapsEX.items_capped? ? pkmn.growth_rate.minimum_exp_for_level(LevelCapsEX.level_cap) : pkmn.growth_rate.maximum_exp
  next [((max_exp - pkmn.exp) / gain_amount.to_f).ceil, 0].max
})

ItemHandlers::UseOnPokemon.add(:EXPCANDYS, proc { |item, qty, pkmn, scene|
  next pbGainExpFromExpCandy(pkmn, 800, qty, scene, item)
})

ItemHandlers::UseOnPokemonMaximum.add(:EXPCANDYM, proc { |item, pkmn|
  gain_amount = 3_000
  max_exp = LevelCapsEX.items_capped? ? pkmn.growth_rate.minimum_exp_for_level(LevelCapsEX.level_cap) : pkmn.growth_rate.maximum_exp
  next [((max_exp - pkmn.exp) / gain_amount.to_f).ceil, 0].max
})

ItemHandlers::UseOnPokemon.add(:EXPCANDYM, proc { |item, qty, pkmn, scene|
  next pbGainExpFromExpCandy(pkmn, 3_000, qty, scene, item)
})

ItemHandlers::UseOnPokemonMaximum.add(:EXPCANDYL, proc { |item, pkmn|
  gain_amount = 10_000
  max_exp = LevelCapsEX.items_capped? ? pkmn.growth_rate.minimum_exp_for_level(LevelCapsEX.level_cap) : pkmn.growth_rate.maximum_exp
  next [((max_exp - pkmn.exp) / gain_amount.to_f).ceil, 0].max
})

ItemHandlers::UseOnPokemon.add(:EXPCANDYL, proc { |item, qty, pkmn, scene|
  next pbGainExpFromExpCandy(pkmn, 10_000, qty, scene, item)
})

ItemHandlers::UseOnPokemonMaximum.add(:EXPCANDYXL, proc { |item, pkmn|
  gain_amount = 30_000
  max_exp = LevelCapsEX.items_capped? ? pkmn.growth_rate.minimum_exp_for_level(LevelCapsEX.level_cap) : pkmn.growth_rate.maximum_exp
  next [((max_exp - pkmn.exp) / gain_amount.to_f).ceil, 0].max
})

ItemHandlers::UseOnPokemon.add(:EXPCANDYXL, proc { |item, qty, pkmn, scene|
  next pbGainExpFromExpCandy(pkmn, 30_000, qty, scene, item)
})

def pbGainExpFromExpCandy(pkmn, base_amt, qty, scene, item)
  if pkmn.level >= GameData::GrowthRate.max_level || pkmn.shadowPokemon?
    scene.pbDisplay(_INTL("It won't have any effect."))
    return false
  end
  
  # Hard cap check - completely prevent exp gain if level cap is reached
  if LevelCapsEX.hard_cap? && pkmn.level >= LevelCapsEX.level_cap
    scene.pbDisplay(_INTL("{1} refuses to eat the {2}.", pkmn.name, GameData::Item.get(item).name))
    return false
  end
  
  # Calculate the maximum Exp the Pokemon can receive. When the active mode
  # caps items (Hard Cap, or EXP Cap with ITEMS_RESPECT_SOFT_CAP), limit to the
  # cap's EXP; otherwise allow up to the species maximum.
  if LevelCapsEX.items_capped?
    max_exp = pkmn.growth_rate.minimum_exp_for_level(LevelCapsEX.level_cap)
  else
    max_exp = pkmn.growth_rate.maximum_exp
  end
  exp_gain = base_amt * qty
  new_exp = pkmn.exp + exp_gain
  
  # If the new Exp would exceed the level cap, limit the Exp gain
  if new_exp > max_exp
    exp_gain = max_exp - pkmn.exp
    if exp_gain <= 0
      scene.pbDisplay(_INTL("{1} refuses to eat the {2}.", pkmn.name, GameData::Item.get(item).name))
      return false
    end
  end
  
  pbSEPlay("Pkmn level up")
  scene.scene.pbSetHelpText("") if scene.is_a?(PokemonPartyScreen)
  if qty > 1
    (qty - 1).times { pkmn.changeHappiness("vitamin") }
  end
  pbChangeExp(pkmn, pkmn.exp + exp_gain, scene)
  scene.pbHardRefresh
  return true
end

#-------------------------------------------------------------------------------
# Additions to Game Variables to log Level Cap changes and set defaults
#-------------------------------------------------------------------------------
class Game_Variables
  alias __level_caps__set_variable []= unless method_defined?(:__level_caps__set_variable)
  def []=(variable_id, value)
    old_value = self[variable_id]
    ret = __level_caps__set_variable(variable_id, value)
    
    if value != old_value
      # Logging for level cap variables (debug only)
      if $DEBUG && LevelCapsEX::LOG_LEVEL_CAP_CHANGES
        if variable_id == LevelCapsEX::LEVEL_CAP_VARIABLE
          echoln "Current Level Cap updated from Lv. #{old_value} to Lv. #{value}"
        elsif variable_id == LevelCapsEX::LEVEL_CAP_MODE_VARIABLE
          mode_names = [
            "None",
            "Hard Cap", 
            "EXP Cap",
            "Obedience Cap"
          ]
          old_name = mode_names[old_value] || "None"
          new_name = mode_names[value] || "None"
          echoln "Current Level Cap Mode updated from \"#{old_name}\" to \"#{new_name}\""
        end
      end
      # Player notification when level cap changes
      if variable_id == LevelCapsEX::LEVEL_CAP_VARIABLE && value > 0 && old_value > 0
        LevelCapsEX.notify_cap_change(old_value, value)
      end
    end
    return ret
  end
end

module Game
  class << self
    alias __level_caps__start_new start_new unless method_defined?(:__level_caps__start_new)
  end

  def self.start_new(*args)
    __level_caps__start_new(*args)
    $game_variables[LevelCapsEX::LEVEL_CAP_MODE_VARIABLE] = LevelCapsEX::DEFAULT_LEVEL_CAP_MODE
    # SC Fix: also seed the cap value so a fresh save isn't effectively
    # uncapped until the first map transition runs the badge-auto-cap.
    if defined?(LevelCapsEX::BADGE_AUTO_CAP) && LevelCapsEX::BADGE_AUTO_CAP
      starting_cap = LevelCapsEX::BADGE_LEVEL_CAPS[0]
      $game_variables[LevelCapsEX::LEVEL_CAP_VARIABLE] = starting_cap if starting_cap
    end
  end
end

#-------------------------------------------------------------------------------
# Main Level Cap Module
#-------------------------------------------------------------------------------
module LevelCapsEX
  module_function

  def level_cap
    return $game_variables[LEVEL_CAP_VARIABLE] if $game_variables && $game_variables[LEVEL_CAP_VARIABLE] > 0
    return Settings::MAXIMUM_LEVEL
  end

  def level_cap_mode
    return 0 unless $game_variables
    lv_cap_mode = $game_variables[LEVEL_CAP_MODE_VARIABLE]
    return lv_cap_mode if [1, 2, 3].include?(lv_cap_mode)
    return 0
  end

  def hard_cap?
    result = level_cap_mode == 1 && $game_variables && $game_variables[LEVEL_CAP_VARIABLE] > 0
    return result
  end

  def soft_cap?
    return $game_variables && level_cap_mode == 2 && $game_variables[LEVEL_CAP_VARIABLE] > 0
  end

  def obedience_cap?
    return $game_variables && level_cap_mode == 3 && $game_variables[LEVEL_CAP_VARIABLE] > 0
  end

  # Whether EXP items (Rare Candy, EXP Candies) should stop AT the cap for the
  # currently active mode. Hard cap always does; EXP/soft cap only when
  # ITEMS_RESPECT_SOFT_CAP is on; obedience and "off" never cap items.
  def items_capped?
    return true if hard_cap?
    return soft_cap? && ITEMS_RESPECT_SOFT_CAP
  end

  def hard_level_cap
    max_lv = Settings::MAXIMUM_LEVEL
    return max_lv if !$game_variables
    lv_cap_mode = $game_variables[LEVEL_CAP_MODE_VARIABLE]
    lv_cap = $game_variables[LEVEL_CAP_VARIABLE]
    return max_lv if lv_cap > max_lv 
    return lv_cap if lv_cap > 0 && lv_cap_mode == 1
    return max_lv
  end
  
  # Check if a Pokemon can gain EXP
  def can_gain_exp?(pokemon)
    return false if hard_cap? && pokemon.level >= level_cap
    return true
  end
  
  # Helper method for compatibility
  def current_level_cap
    cap_value = $game_variables ? $game_variables[LEVEL_CAP_VARIABLE] : nil
    return cap_value if cap_value && cap_value > 0
    return Settings::MAXIMUM_LEVEL
  end
  
  # Check if Voltseon's Pause Menu exists
  def voltseons_pause_menu_exists?
    return defined?(VoltseonsPauseMenu_Scene)
  end
end

#-------------------------------------------------------------------------------
# Voltseon's Pause Menu Integration (if available)
#-------------------------------------------------------------------------------
if LevelCapsEX.voltseons_pause_menu_exists?
  class VPM_LevelCapHud < Component
    def start_component(viewport, menu)
      super(viewport, menu)
      @sprites["overlay"] = BitmapSprite.new(Graphics.width / 2, 32, viewport)
      @sprites["overlay"].ox = @sprites["overlay"].bitmap.width
      @sprites["overlay"].x = Graphics.width
      @sprites["overlay"].y = 90
      @base_color = $PokemonSystem.from_current_menu_theme(MENU_TEXTCOLOR, Color.new(248, 248, 248))
      @shdw_color = $PokemonSystem.from_current_menu_theme(MENU_TEXTOUTLINE, Color.new(48, 48, 48))
    end

    def should_draw?; return true; end

    def refresh
      level_cap = LevelCapsEX.current_level_cap
      text = _INTL("Level Cap: {1}", level_cap)
      @sprites["overlay"].bitmap.clear
      pbSetSystemFont(@sprites["overlay"].bitmap)
      pbDrawTextPositions(@sprites["overlay"].bitmap, [
        [text, (Graphics.width / 2) - 8, 12, 1, @base_color, @shdw_color]
      ])
    end
  end

  # Add the component to the menu if MENU_COMPONENTS is defined
  MENU_COMPONENTS << :VPM_LevelCapHud if defined?(MENU_COMPONENTS)
end

#===============================================================================
# Badge-Based Auto Level Cap
# Automatically updates the level cap when the player earns a new badge.
#===============================================================================
if LevelCapsEX::BADGE_AUTO_CAP
  module LevelCapsEX
    module_function

    # Track the last badge count we processed so we only fire on actual
    # changes. The authoritative value is persisted in $PokemonGlobal (see
    # below); this module ivar is only a fallback before $PokemonGlobal exists.
    @last_badge_count = -1

    def update_cap_for_badges
      return if !$game_variables || !$player
      badge_count = $player.badge_count
      # Read/write the persisted counter when available so a manually or
      # event-lowered cap survives save/load and map changes instead of being
      # bumped straight back up to the badge cap.
      last = $PokemonGlobal ? ($PokemonGlobal.level_cap_last_badge_count || -1) : @last_badge_count
      return if badge_count == last
      if $PokemonGlobal
        $PokemonGlobal.level_cap_last_badge_count = badge_count
      else
        @last_badge_count = badge_count
      end
      cap = BADGE_LEVEL_CAPS[badge_count]
      return if !cap
      current = $game_variables[LEVEL_CAP_VARIABLE]
      if cap > current
        $game_variables[LEVEL_CAP_VARIABLE] = cap
        # Award any stored EXP from the piggy bank
        award_stored_exp if EXP_STORAGE_ENABLED
      end
    end
  end

  # Check badge count on map transitions — catches badge grants from events
  EventHandlers.add(:on_enter_map, :level_cap_badge_check,
    proc { |_old_map_id|
      LevelCapsEX.update_cap_for_badges if LevelCapsEX::BADGE_AUTO_CAP
    }
  )

  # Also check after battle ends (badge often granted post-gym-battle)
  EventHandlers.add(:on_end_battle, :level_cap_badge_check_battle,
    proc { |_decision, _can_lose|
      LevelCapsEX.update_cap_for_badges if LevelCapsEX::BADGE_AUTO_CAP
    }
  )
end

#===============================================================================
# EXP Storage (Piggy Bank) System
# Stores blocked EXP during hard cap. Awards it when the cap increases.
#===============================================================================
#-------------------------------------------------------------------------------
# Persist stored EXP data in $PokemonGlobal so it survives save/load
#-------------------------------------------------------------------------------
class PokemonGlobalMetadata
  attr_writer :level_cap_stored_exp
  # Persisted across save/load so the badge auto-cap doesn't re-raise a
  # manually/event-lowered cap on every load or map transition.
  attr_accessor :level_cap_last_badge_count

  def level_cap_stored_exp
    @level_cap_stored_exp = {} if !@level_cap_stored_exp.is_a?(Hash)
    return @level_cap_stored_exp
  end
end

module LevelCapsEX
  module_function

  def stored_exp
    return $PokemonGlobal.level_cap_stored_exp if $PokemonGlobal
    # Fallback for early init before $PokemonGlobal exists
    @stored_exp ||= {}
    return @stored_exp
  end

  # Estimate the EXP a Pokemon would have gained
  def store_blocked_exp(pkmn, idx_party, defeated_battler, num_partic, exp_share, exp_all, trainer_battle = false)
    return if !EXP_STORAGE_ENABLED
    level = defeated_battler.level
    a = level * defeated_battler.pokemon.base_exp
    pid = pkmn.personalID
    is_partic = defeated_battler.participants.include?(idx_party)
    has_share = exp_share.include?(idx_party)
    # Participation / Exp Share split (mirrors pbGainExpOne's SPLIT path).
    exp = 0
    if has_share && is_partic
      exp = a / (2 * [num_partic, 1].max) + a / (2 * [exp_share.length, 1].max)
    elsif has_share
      exp = a / [exp_share.length, 1].max
    elsif is_partic
      exp = a / [num_partic, 1].max
    elsif exp_all
      exp = a / 2
    else
      return  # Pokemon didn't participate and has no Exp Share — no blocked EXP
    end
    return if exp <= 0
    # Trainer-battle bonus (applied before scaling, as in pbGainExpOne).
    exp = (exp * 1.5).floor if Settings::MORE_EXP_FROM_TRAINER_POKEMON && trainer_battle
    # Level scaling — the big factor the old estimate skipped, which made the
    # bank roughly 5-7x too high. Mirrors pbGainExpOne. Still an estimate: it
    # omits the held-item Exp modifier and the affection bonus, which need
    # battler context we don't have here.
    if Settings::SCALED_EXP_FORMULA
      exp /= 5
      level_adjust = ((2 * level) + 10.0) / (pkmn.level + level + 10.0)
      level_adjust **= 5
      level_adjust = Math.sqrt(level_adjust)
      exp = (exp * level_adjust).floor
      exp += 1 if is_partic || has_share
    else
      exp /= 7
    end
    # Foreign-Pokemon bonus (mirrors pbGainExpOne).
    if $player
      is_outsider = (pkmn.owner.id != $player.id ||
                     (pkmn.owner.language != 0 && pkmn.owner.language != $player.language))
      if is_outsider
        if pkmn.owner.language != 0 && pkmn.owner.language != $player.language
          exp = (exp * 1.7).floor
        else
          exp = (exp * 1.5).floor
        end
      end
    end
    # Exp. Charm.
    exp = exp * 3 / 2 if $bag&.has?(:EXPCHARM)
    exp = [exp, 1].max
    stored_exp[pid] ||= 0
    stored_exp[pid] += exp
  end

  # Pay out a single Pokemon's banked EXP, capped so it can't exceed the new
  # level cap. `verbose` controls the "grew to Lv." message and on-map
  # evolution (party only — boxed Pokemon are paid out silently).
  def apply_stored_exp(pkmn, verbose)
    return if !pkmn || pkmn.egg?
    pid = pkmn.personalID
    banked = stored_exp[pid]
    return if !banked || banked <= 0
    # Cap the award so it doesn't exceed the new level cap
    max_exp = pkmn.growth_rate.minimum_exp_for_level(level_cap)
    award = [banked, [max_exp - pkmn.exp, 0].max].min
    if award > 0
      pkmn.exp += award
      old_level = pkmn.level
      pkmn.calc_stats
      new_level = pkmn.level
      if new_level > old_level
        pbMessage(_INTL("{1} grew to Lv. {2} from stored Exp!", pkmn.name, new_level)) if verbose
        # Learn moves for all gained levels
        move_list = pkmn.getMoveList
        (old_level + 1..new_level).each do |lv|
          move_list.each { |m| pbLearnMove(pkmn, m[1]) if m[0] == lv }
        end
        # Trigger a pending level-up evolution — party only, and only on the
        # map (award_stored_exp can run from on_end_battle, where a full
        # evolution scene isn't safe; boxed Pokemon never show one).
        if verbose && $scene.is_a?(Scene_Map)
          new_species = pkmn.check_evolution_on_level_up
          if new_species
            pbFadeOutInWithMusic do
              evo = PokemonEvolutionScene.new
              evo.pbStartScreen(pkmn, new_species)
              evo.pbEvolution
              evo.pbEndScreen
            end
          end
        end
      end
    end
    stored_exp.delete(pid)
  end

  # Award all stored EXP. Party Pokemon get the full treatment (messages +
  # on-map evolution); boxed Pokemon are paid out silently so their bank is
  # never lost. Leftover entries belong to released/traded Pokemon and are
  # cleared so the bank can't grow unbounded.
  def award_stored_exp
    return if !$player || stored_exp.empty?
    $player.party.each { |pkmn| apply_stored_exp(pkmn, true) }
    if $PokemonStorage
      (0...$PokemonStorage.maxBoxes).each do |b|
        (0...$PokemonStorage.maxPokemon(b)).each do |i|
          apply_stored_exp($PokemonStorage[b, i], false)
        end
      end
    end
    stored_exp.clear
  end
end

#===============================================================================
# Level Cap Change Notification
#===============================================================================
module LevelCapsEX
  module_function

  def notify_cap_change(old_value, new_value)
    return if old_value == new_value
    return if !$scene || !$scene.is_a?(Scene_Map)
    if new_value > old_value
      pbMessage(_INTL("\\se[Pkmn level up]Level Cap increased to Lv. {1}!", new_value))
    elsif new_value < old_value
      pbMessage(_INTL("Level Cap decreased to Lv. {1}.", new_value))
    end
  end
end

#===============================================================================
# Party Screen — Level Cap Color Indicator
# Colors the level number orange when at cap, red when above cap.
#===============================================================================
class PokemonPartyPanel < Sprite
  LEVEL_CAP_COLOR        = Color.new(255, 165, 0)     # Orange — at cap
  LEVEL_CAP_SHADOW       = Color.new(160, 80, 0)
  LEVEL_OVER_CAP_COLOR   = Color.new(255, 50, 50)     # Red — above cap
  LEVEL_OVER_CAP_SHADOW  = Color.new(160, 20, 20)

  alias __level_cap_draw_level draw_level unless method_defined?(:__level_cap_draw_level)

  def draw_level
    return if @pokemon.egg?
    # "Lv" graphic
    pbDrawImagePositions(@overlaysprite.bitmap,
                         [[_INTL("Graphics/UI/Party/overlay_lv"), 20, 70, 0, 0, 22, 14]])
    # Determine color based on level cap status
    base_color   = TEXT_BASE_COLOR
    shadow_color = TEXT_SHADOW_COLOR
    if defined?(LevelCapsEX) && (LevelCapsEX.hard_cap? || LevelCapsEX.soft_cap? || LevelCapsEX.obedience_cap?)
      cap = LevelCapsEX.level_cap
      if @pokemon.level > cap
        base_color   = LEVEL_OVER_CAP_COLOR
        shadow_color = LEVEL_OVER_CAP_SHADOW
      elsif @pokemon.level == cap
        base_color   = LEVEL_CAP_COLOR
        shadow_color = LEVEL_CAP_SHADOW
      end
    end
    # Level number
    pbSetSmallFont(@overlaysprite.bitmap)
    pbDrawTextPositions(@overlaysprite.bitmap,
                        [[@pokemon.level.to_s, 42, 68, :left, base_color, shadow_color]])
    pbSetSystemFont(@overlaysprite.bitmap)
  end
end

#===============================================================================
# Summary Screen — Level Cap Indicator (SV Summary compatible)
# Draws colored label + stored EXP info on the info page when at/above cap.
#===============================================================================
class PokemonSummary_Scene
  alias __level_cap_drawPageOne drawPageOne unless method_defined?(:__level_cap_drawPageOne)

  def drawPageOne
    __level_cap_drawPageOne
    return if @pokemon.egg?
    return if !(LevelCapsEX.hard_cap? || LevelCapsEX.soft_cap? || LevelCapsEX.obedience_cap?)
    overlay = @sprites["overlay"].bitmap
    cap = LevelCapsEX.level_cap
    return if @pokemon.level < cap
    if @pokemon.level > cap
      base   = Color.new(255, 50, 50)
      shadow = Color.new(160, 20, 20)
      label  = _INTL("Over Level Cap!")
    else
      base   = Color.new(255, 165, 0)
      shadow = Color.new(160, 80, 0)
      label  = _INTL("At Level Cap")
    end
    pbDrawTextPositions(overlay, [[label, 504, 240, :right, base, shadow]])
    # Show stored EXP amount if the piggy bank has anything
    if LevelCapsEX::EXP_STORAGE_ENABLED
      banked = LevelCapsEX.stored_exp[@pokemon.personalID] || 0
      if banked > 0
        pbDrawTextPositions(overlay,
          [[_INTL("Stored Exp: {1}", banked.to_s_formatted), 504, 260, :right,
            Color.new(120, 200, 255), Color.new(50, 100, 150)]])
      end
    end
  end
end

#===============================================================================
# Debug Menu Commands
#===============================================================================
if $DEBUG
  MenuHandlers.add(:debug_menu, :level_cap_menu, {
    "name"        => _INTL("Level Cap options..."),
    "parent"      => :field_menu,
    "description" => _INTL("Set level cap, cap mode, view stored EXP, and other Level Caps Ex options.")
  })

  MenuHandlers.add(:debug_menu, :level_cap_set_cap, {
    "name"        => _INTL("Set Level Cap"),
    "parent"      => :level_cap_menu,
    "description" => _INTL("Change the current level cap value."),
    "effect"      => proc {
      current = $game_variables[LevelCapsEX::LEVEL_CAP_VARIABLE]
      params = ChooseNumberParams.new
      params.setRange(1, Settings::MAXIMUM_LEVEL)
      params.setDefaultValue(current)
      new_cap = pbMessageChooseNumber(_INTL("Set the level cap (current: {1}).", current), params)
      if new_cap != current
        $game_variables[LevelCapsEX::LEVEL_CAP_VARIABLE] = new_cap
        pbMessage(_INTL("Level cap set to {1}.", new_cap))
      end
    }
  })

  MenuHandlers.add(:debug_menu, :level_cap_set_mode, {
    "name"        => _INTL("Set Level Cap Mode"),
    "parent"      => :level_cap_menu,
    "description" => _INTL("Change the level cap mode (Hard/Soft/Obedience/Off)."),
    "effect"      => proc {
      current = $game_variables[LevelCapsEX::LEVEL_CAP_MODE_VARIABLE]
      mode_names = ["Off (0)", "Hard Cap (1)", "Soft/EXP Cap (2)", "Obedience Cap (3)"]
      choice = pbMessage(_INTL("Current mode: {1}. Choose new mode:", mode_names[current] || "Off"),
                         mode_names, -1)
      if choice >= 0 && choice != current
        $game_variables[LevelCapsEX::LEVEL_CAP_MODE_VARIABLE] = choice
        pbMessage(_INTL("Level cap mode set to {1}.", mode_names[choice]))
      end
    }
  })

  MenuHandlers.add(:debug_menu, :level_cap_view_stored_exp, {
    "name"        => _INTL("View Stored EXP"),
    "parent"      => :level_cap_menu,
    "description" => _INTL("View the EXP piggy bank for each party Pokémon."),
    "effect"      => proc {
      if !LevelCapsEX::EXP_STORAGE_ENABLED
        pbMessage(_INTL("EXP Storage is disabled in config."))
        next
      end
      lines = []
      $player.party.each do |pkmn|
        next if !pkmn || pkmn.egg?
        banked = LevelCapsEX.stored_exp[pkmn.personalID] || 0
        lines.push(_INTL("{1} (Lv.{2}): {3} stored EXP", pkmn.name, pkmn.level, banked))
      end
      if lines.empty?
        pbMessage(_INTL("No Pokémon in party."))
      else
        pbMessage(lines.join("\n"))
      end
    }
  })

  MenuHandlers.add(:debug_menu, :level_cap_award_stored, {
    "name"        => _INTL("Award Stored EXP Now"),
    "parent"      => :level_cap_menu,
    "description" => _INTL("Immediately award all stored EXP to party Pokémon."),
    "effect"      => proc {
      if !LevelCapsEX::EXP_STORAGE_ENABLED
        pbMessage(_INTL("EXP Storage is disabled in config."))
        next
      end
      if LevelCapsEX.stored_exp.empty?
        pbMessage(_INTL("No stored EXP to award."))
        next
      end
      LevelCapsEX.award_stored_exp
      pbMessage(_INTL("Stored EXP has been awarded."))
    }
  })

  MenuHandlers.add(:debug_menu, :level_cap_clear_stored, {
    "name"        => _INTL("Clear All Stored EXP"),
    "parent"      => :level_cap_menu,
    "description" => _INTL("Delete all stored EXP data (cannot be undone)."),
    "effect"      => proc {
      if LevelCapsEX.stored_exp.empty?
        pbMessage(_INTL("No stored EXP to clear."))
        next
      end
      if pbConfirmMessage(_INTL("Clear ALL stored EXP? This cannot be undone."))
        LevelCapsEX.stored_exp.clear
        pbMessage(_INTL("All stored EXP cleared."))
      end
    }
  })

  MenuHandlers.add(:debug_menu, :level_cap_toggle_bypass, {
    "name"        => _INTL("Toggle Level Cap Bypass"),
    "parent"      => :level_cap_menu,
    "description" => _INTL("Toggle the bypass switch that disables level caps for enemies."),
    "effect"      => proc {
      sw = LevelCapsEX::LEVEL_CAP_BYPASS_SWITCH
      $game_switches[sw] = !$game_switches[sw]
      state = $game_switches[sw] ? "ON" : "OFF"
      pbMessage(_INTL("Level Cap Bypass Switch is now {1}.", state))
    }
  })
end
