#===============================================================================
# [SC] Level Caps Ex - Main (v2.7.0)
# Shattered Crowns fork of Level Caps EX v2.3.2
# Restores the v2.5.1 correctness fixes (soft cap no longer clamps level;
# no destructive pbGainExp override; obedience fires even with all badges)
# that a later bulk commit reverted, plus assorted audit fixes.
#===============================================================================

#-------------------------------------------------------------------------------
# Hard Level Cap related Additions
#-------------------------------------------------------------------------------
class Pokemon
  alias level_caps_level_equals level= unless method_defined?(:level_caps_level_equals)
  
  def level=(value)
    validate value => Integer
    if value < 1 || value > GameData::GrowthRate.max_level
      max_lvl = GameData::GrowthRate.max_level
      limit = (value < 1)? ["below the minimum of level 1", "1"] : ["above the maximum of level #{max_lvl}", "#{max_lvl}"]
      echoln _INTL("Level {1} for {2} is not a valid level as it goes {3}. The level has been reset to {4}",
                    value, self, limit[0], limit[1])
      value = value.clamp(1, GameData::GrowthRate.max_level)
    end
    
    # Additional check for level caps - but respect bypass switch
    # SC Fix: Guard against $game_switches being nil during early initialization
    # Mode behaviour:
    #   * Hard Cap (1)       — clamp the level at the cap (EXP is also blocked).
    #   * Soft / EXP Cap (2) — do NOT clamp; the Pokemon may cross the cap and
    #     EXP gain past it is just heavily reduced (see pbGainExpOne). Clamping
    #     here would make mode 2 indistinguishable from mode 1.
    #   * Obedience Cap (3)  — do NOT clamp; overlevel triggers disobedience.
    if $game_switches && !$game_switches[LevelCapsEX::LEVEL_CAP_BYPASS_SWITCH]
      if LevelCapsEX.hard_cap? && value > LevelCapsEX.level_cap
        value = LevelCapsEX.level_cap
      end
    end
    
    @exp = growth_rate.minimum_exp_for_level(value)
    @level = value
  end

  def at_level_cap?
    return (LevelCapsEX.hard_cap? || LevelCapsEX.soft_cap?) && self.level >= LevelCapsEX.level_cap
  end

  # Alias for backwards compatibility
  alias crosses_level_cap? at_level_cap?

  def level
    @level = growth_rate.level_from_exp(@exp) if !@level
    self.level = GameData::GrowthRate.max_level if @level > GameData::GrowthRate.max_level
    return @level
  end
end

module GameData
  class GrowthRate
    def self.max_level
      return LevelCapsEX.hard_level_cap
    end
  end
end

#-------------------------------------------------------------------------------
# Soft Level Cap related Additions
#-------------------------------------------------------------------------------
class Battle
  alias __level_caps_initialize initialize unless method_defined?(:__level_caps_initialize)
  
  def initialize(*args)
    __level_caps_initialize(*args)
    
    # SC Fix: Guard against $game_switches being nil
    if $game_switches && $game_switches[LevelCapsEX::LEVEL_CAP_BYPASS_SWITCH]
      return
    end
    
    # SC Fix: only clamp opponents when an actual cap mode is active.
    # Obedience Cap is meant to LET enemies be overleveled; Off mode
    # shouldn't clamp anything either. Only Hard/Soft caps clamp.
    return unless LevelCapsEX.hard_cap? || LevelCapsEX.soft_cap?
    
    # Apply level caps to opponent Pokemon only if bypass is OFF
    if opponent && opponent.is_a?(Array)
      opponent.each do |trainer|
        next if !trainer || !trainer.party
        trainer.party.each do |pkmn|
          next if !pkmn
          if pkmn.level > LevelCapsEX.level_cap
            pkmn.level = LevelCapsEX.level_cap
            pkmn.calc_stats
          end
        end
      end
    end
  end

  # NOTE: An earlier "fallback protection" override of pbGainExp removed
  # at-cap Pokemon from `b.participants` before calling the original. That
  # caused two problems:
  #   1. If the lead was the only participant and was at the cap, the
  #      participants list became empty. Essentials' pbGainExp then hit
  #      `next if b.participants.length == 0` and skipped that defeated
  #      battler entirely — so Exp Share / Exp All recipients (including
  #      benched Pokemon below the cap) got nothing.
  #   2. Permanently mutating `b.participants` leaked into other systems
  #      that read the same list (EVs, friendship, captured-Pokemon stats).
  # The per-recipient block in pbGainExpOne below is sufficient — it fires
  # for participants, Exp Share holders, and Exp All recipients alike with
  # no list mutation needed.

  alias __level_caps_pbGainExpOne pbGainExpOne unless method_defined?(:__level_caps_pbGainExpOne)

  # ---------------------------------------------------------------------------
  # SC FIX (review C2): pbGainExpOne is unfortunately a full rewrite of
  # Essentials' default in order to slot in soft-cap EXP reduction MID-formula.
  # However, in the common cases (no cap active, or under-cap) we can delegate
  # to the alias chain — this preserves any pbGainExpOne modifications from
  # plugins that load BEFORE Level Caps Ex (DBK, AAI, etc.), which would
  # otherwise be silently wiped by the rewrite below.
  # ---------------------------------------------------------------------------
  def pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages = true)
    pkmn = pbParty(0)[idxParty]   # The Pokémon gaining Exp from defeatedBattler
    return unless pkmn # safety: party slot may be nil during certain hooks
    growth_rate = pkmn.growth_rate

    # Hard level cap check - completely block exp gain
    if LevelCapsEX.hard_cap? && pkmn.level >= LevelCapsEX.level_cap
      # Store blocked EXP if storage is enabled (awarded when cap increases)
      if LevelCapsEX::EXP_STORAGE_ENABLED
        LevelCapsEX.store_blocked_exp(pkmn, idxParty, defeatedBattler, numPartic, expShare, expAll, trainerBattle?)
      end
      return
    end

    # Soft / Obedience cap — by default, at-cap Pokemon should NOT pick up
    # passive Exp Share / Exp All gains. Direct participation still leaks
    # through (and goes through the soft cap's reduction curve below).
    # Toggle via SHARED_EXP_RESPECTS_CAP.
    if LevelCapsEX::SHARED_EXP_RESPECTS_CAP &&
       (LevelCapsEX.soft_cap? || LevelCapsEX.obedience_cap?) &&
       pkmn.level >= LevelCapsEX.level_cap
      return if !defeatedBattler.participants.include?(idxParty)
    end

    # Fast path: when no cap reduction needs to fire mid-formula, delegate to
    # the alias chain so other plugins' pbGainExpOne hooks remain effective.
    soft_cap_active = LevelCapsEX.soft_cap? && pkmn.level >= LevelCapsEX.level_cap
    hard_cap_clamp_needed = LevelCapsEX.hard_cap? # may need to clamp final exp at cap level
    unless soft_cap_active || hard_cap_clamp_needed
      return __level_caps_pbGainExpOne(idxParty, defeatedBattler, numPartic, expShare, expAll, showMessages)
    end

    # Don't bother calculating if gainer is already at max Exp
    if pkmn.exp >= growth_rate.maximum_exp
      pkmn.calc_stats   # To ensure new EVs still have an effect
      return
    end
    isPartic    = defeatedBattler.participants.include?(idxParty)
    hasExpShare = expShare.include?(idxParty)
    level = defeatedBattler.level
    # Main Exp calculation
    exp = 0
    a = level * defeatedBattler.pokemon.base_exp
    if expShare.length > 0 && (isPartic || hasExpShare)
      if numPartic == 0   # No participants, all Exp goes to Exp Share holders
        exp = a / (Settings::SPLIT_EXP_BETWEEN_GAINERS ? expShare.length : 1)
      elsif Settings::SPLIT_EXP_BETWEEN_GAINERS   # Gain from participating and/or Exp Share
        exp = a / (2 * numPartic) if isPartic
        exp += a / (2 * expShare.length) if hasExpShare
      else   # Gain from participating and/or Exp Share (Exp not split)
        exp = (isPartic) ? a : a / 2
      end
    elsif isPartic   # Participated in battle, no Exp Shares held by anyone
      exp = a / (Settings::SPLIT_EXP_BETWEEN_GAINERS ? numPartic : 1)
    elsif expAll   # Didn't participate in battle, gaining Exp due to Exp All
      # NOTE: Exp All works like the Exp Share from Gen 6+, not like the Exp All
      #       from Gen 1, i.e. Exp isn't split between all Pokémon gaining it.
      exp = a / 2
    end
    return if exp <= 0
    # Pokémon gain more Exp from trainer battles
    exp = (exp * 1.5).floor if Settings::MORE_EXP_FROM_TRAINER_POKEMON && trainerBattle?
    # Scale the gained Exp based on the gainer's level (or not)
    if Settings::SCALED_EXP_FORMULA
      exp /= 5
      levelAdjust = ((2 * level) + 10.0) / (pkmn.level + level + 10.0)
      levelAdjust **= 5
      levelAdjust = Math.sqrt(levelAdjust)
      exp *= levelAdjust
      exp = exp.floor
      exp += 1 if isPartic || hasExpShare
    else
      exp /= 7
    end
    # Foreign Pokémon gain more Exp
    isOutsider = (pkmn.owner.id != pbPlayer.id ||
                 (pkmn.owner.language != 0 && pkmn.owner.language != pbPlayer.language))
    if isOutsider
      if pkmn.owner.language != 0 && pkmn.owner.language != pbPlayer.language
        exp = (exp * 1.7).floor
      else
        exp = (exp * 1.5).floor
      end
    end
    # Exp. Charm increases Exp gained
    exp = exp * 3 / 2 if $bag.has?(:EXPCHARM)
    # Modify Exp gain based on pkmn's held item
    i = Battle::ItemEffects.triggerExpGainModifier(pkmn.item, pkmn, exp)
    if i < 0
      i = Battle::ItemEffects.triggerExpGainModifier(@initialItems[0][idxParty], pkmn, exp)
    end
    exp = i if i >= 0
    # Boost Exp gained with high affection
    if Settings::AFFECTION_EFFECTS && @internalBattle && pkmn.affection_level >= 4 && !pkmn.mega?
      exp = exp * 6 / 5
      isOutsider = true   # To show the "boosted Exp" message
    end
    # Modify exp gain based on soft level cap
    over_level_cap = false
    if LevelCapsEX.soft_cap? && pkmn.level >= LevelCapsEX.level_cap
      over_level_cap = true
      levels_over = pkmn.level - LevelCapsEX.level_cap
      if LevelCapsEX::SOFT_CAP_SCALED
        # Smooth curve: 50% per level over, minimum 1% 
        reduction = [0.5 ** (levels_over + 1), 0.01].max
        exp = (exp * reduction).to_i
      else
        # Original flat 1/10 reduction
        exp = (exp / 10).to_i
      end
      exp = 1 if exp < 1
    end
    # Make sure Exp doesn't exceed the maximum
    expFinal = growth_rate.add_exp(pkmn.exp, exp)
    
    # Add additional check: don't let experience exceed level cap if hard cap is on
    if LevelCapsEX.hard_cap?
      max_exp_allowed = growth_rate.minimum_exp_for_level(LevelCapsEX.level_cap)
      expFinal = [expFinal, max_exp_allowed].min
    end
    
    expGained = expFinal - pkmn.exp
    return if expGained <= 0
    # "Exp gained" message
    if showMessages
      message = _INTL("{1} got {2} Exp. Points!", pkmn.name, expGained)
      message = _INTL("{1} got a boosted {2} Exp. Points!", pkmn.name, expGained) if isOutsider
      message = _INTL("{1} got a reduced {2} Exp. Points!", pkmn.name, expGained) if over_level_cap
      pbDisplayPaused(message)
    end
    curLevel = pkmn.level
    newLevel = growth_rate.level_from_exp(expFinal)
    if newLevel < curLevel
      debugInfo = "Levels: #{curLevel}->#{newLevel} | Exp: #{pkmn.exp}->#{expFinal} | gain: #{expGained}"
      raise _INTL("{1}'s new level is less than its current level, which shouldn't happen.", pkmn.name) + "\n[#{debugInfo}]"
    end
    # Give Exp
    if pkmn.shadowPokemon?
      if pkmn.heartStage <= 3
        pkmn.exp += expGained
        $stats.total_exp_gained += expGained
      end
      return
    end
    $stats.total_exp_gained += expGained
    tempExp1 = pkmn.exp
    
    # Additional safety check: prevent level-up loop if at hard cap
    if LevelCapsEX.hard_cap? && newLevel > LevelCapsEX.level_cap
      newLevel = LevelCapsEX.level_cap
    end
    battler = pbFindBattler(idxParty)
    loop do   # For each level gained in turn...
      # EXP Bar animation
      levelMinExp = growth_rate.minimum_exp_for_level(curLevel)
      levelMaxExp = growth_rate.minimum_exp_for_level(curLevel + 1)
      tempExp2 = (levelMaxExp < expFinal) ? levelMaxExp : expFinal
      pkmn.exp = tempExp2
      @scene.pbEXPBar(battler, levelMinExp, levelMaxExp, tempExp1, tempExp2)
      tempExp1 = tempExp2
      curLevel += 1
      if curLevel > newLevel
        # Gained all the Exp now, end the animation
        pkmn.calc_stats
        battler&.pbUpdate(false)
        @scene.pbRefreshOne(battler.index) if battler
        break
      end
      # Levelled up
      pbCommonAnimation("LevelUp", battler) if battler
      oldTotalHP = pkmn.totalhp
      oldAttack  = pkmn.attack
      oldDefense = pkmn.defense
      oldSpAtk   = pkmn.spatk
      oldSpDef   = pkmn.spdef
      oldSpeed   = pkmn.speed
      battler.pokemon.changeHappiness("levelup") if battler&.pokemon
      pkmn.calc_stats
      battler&.pbUpdate(false)
      @scene.pbRefreshOne(battler.index) if battler
      pbDisplayPaused(_INTL("{1} grew to Lv. {2}!", pkmn.name, curLevel)) { pbSEPlay("Pkmn level up") }
      @scene.pbLevelUp(pkmn, battler, oldTotalHP, oldAttack, oldDefense,
                       oldSpAtk, oldSpDef, oldSpeed)
      # Learn all moves learned at this level
      moveList = pkmn.getMoveList
      moveList.each { |m| pbLearnMove(idxParty, m[1]) if m[0] == curLevel }
    end
  end
end

#-------------------------------------------------------------------------------
# Obedience Related Level Cap Additions
#-------------------------------------------------------------------------------
class Battle::Battler

  alias __level_cap__pbObedienceCheck? pbObedienceCheck? unless method_defined?(:__level_cap__pbObedienceCheck?)
  def pbObedienceCheck?(*args)
    ret = __level_cap__pbObedienceCheck?(*args)
    db = @disobeyed
    @disobeyed = false
    # If the base check already triggered disobedience this turn, respect it.
    return ret if db
    # If the base check decided to disobey (returned false), respect that too.
    return ret unless ret
    # Otherwise the base check said "obey" — but the player might have all
    # badges, which short-circuits Essentials' obedience entirely. We still
    # want our level-cap obedience to fire for overlevelled Pokemon, so the
    # check below runs regardless of the base result.
    return true unless LevelCapsEX.obedience_cap?
    lv_diff = @level - LevelCapsEX.level_cap
    return true if lv_diff <= 0
    lv_diff = 5 if lv_diff > 5
    # lv_diff is clamped to 1..5 above; a range of 0 (lv_diff == 5) means the
    # Pokemon always disobeys. Computing the range first avoids rand(0).
    range = 5 - lv_diff
    disobedient = range <= 0 || rand(range) == 0
    return pbDisobey(args[0], (lv_diff * 2)) if disobedient
    return true
  end

  alias __level_cap__pbDisobey pbDisobey unless method_defined?(:__level_cap__pbDisobey)
  def pbDisobey(*args)
    ret = __level_cap__pbDisobey(*args)
    @disobeyed = true
    return ret
  end
end

#-------------------------------------------------------------------------------
# Fix for battle system: Prevents opponent from sending out fainted Pokémon
#-------------------------------------------------------------------------------
class Battle::AI
  alias __level_caps_pbDefaultChooseNewEnemy pbDefaultChooseNewEnemy unless method_defined?(:__level_caps_pbDefaultChooseNewEnemy)
  
  def pbDefaultChooseNewEnemy(idxBattler = @idxBattler)
    # Get the original result
    ret = __level_caps_pbDefaultChooseNewEnemy(idxBattler)
    
    # Check if the selected Pokémon is able to battle
    if ret && ret >= 0
      party = @battle.pbParty(@idxBattler)
      if ret < party.length && !party[ret].able?
        # The chosen Pokémon is not able to battle, find another one
        new_choice = -1
        party.each_with_index do |pkmn, i|
          next if !pkmn || !pkmn.able? || @battle.pbFindBattler(i, @idxBattler)
          new_choice = i
          break
        end
        ret = new_choice
      end
    end
    
    return ret
  end
end

#-------------------------------------------------------------------------------
# Fix for Level Caps EX causing PBS compilation to fail
#-------------------------------------------------------------------------------
module GameData
  class GrowthRate
    # Store original max level value from Settings
    @original_max_level = Settings::MAXIMUM_LEVEL
    
    class << self
      alias_method :original_max_level, :max_level unless method_defined?(:original_max_level)
      
      def max_level
        # WARNING — DO NOT "simplify" this method. `FileLineData` is a
        # permanently-loaded compiler module, so `defined?(FileLineData)` is
        # ALWAYS true at runtime. This method therefore effectively always
        # returns the game's original maximum (e.g. 100), NOT the level cap.
        # That is intentional and load-bearing: if it returned the cap,
        # Pokemon#level (which clamps @level to max_level on every read) would
        # force overlevelled Obedience-Cap Pokemon back down to the cap and
        # break mode 3 entirely. The cap is enforced where it belongs — the
        # level= setter, pbGainExpOne, and the battle/trainer clamps.
        if defined?(FileLineData) || caller.any? { |c| c.include?("compile") }
          return @original_max_level || Settings::MAXIMUM_LEVEL
        end
        # Effectively unreachable at runtime today (see warning above); kept
        # only to document the original intent.
        return LevelCapsEX.hard_level_cap
      end
    end
  end
end

#-------------------------------------------------------------------------------
# SC Fix: PE v21.1 uses `Trainer` (with `Player < Trainer`); the legacy
# `Pokemon_Trainer` name from Essentials v18 doesn't exist anymore. Hooking
# `Trainer#initialize` ensures the level-cap clamp actually runs whenever a
# Trainer (including the player) is rebuilt from save data.
#-------------------------------------------------------------------------------
class Trainer
  alias __level_caps_initialize initialize unless method_defined?(:__level_caps_initialize)

  def initialize(*args)
    __level_caps_initialize(*args)
    enforce_level_cap
  end

  def enforce_level_cap
    # SC Fix: Guard against $game_switches being nil during early initialization
    return if !$game_switches
    return if $game_switches[LevelCapsEX::LEVEL_CAP_BYPASS_SWITCH]
    return unless LevelCapsEX.hard_cap? || LevelCapsEX.soft_cap?
    # Skip if we've already clamped this instance — Trainer objects may be
    # Marshalled (raid partners, AI clones) and unmarshalled trainers re-enter
    # initialize. Without this guard, the clamp would compound with other
    # plugins' party mutations (e.g. Trainer Scaling).
    return if @_level_cap_enforced
    @_level_cap_enforced = true

    cap = LevelCapsEX.level_cap
    @party&.each do |pkmn|
      next if !pkmn
      if pkmn.level > cap
        pkmn.level = cap
        pkmn.calc_stats
      end
    end
  end
end
