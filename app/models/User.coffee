GRAVATAR_URL = 'https://www.gravatar.com/'
cache = {}
CocoModel = require './CocoModel'
util = require 'lib/utils'

module.exports = class User extends CocoModel
  @className: 'User'
  @schema: require 'schemas/models/user'
  urlRoot: '/db/user'
  notyErrors: false

  onLoaded:  ->
    CocoModel.pollAchievements() # Check for achievements on login
    super arguments...

  isAdmin: -> 'admin' in @get('permissions', true)
  isAnonymous: -> @get('anonymous', true)
  displayName: -> @get('name', true)

  getPhotoURL: (size=80, useJobProfilePhoto=false, useEmployerPageAvatar=false) ->
    photoURL = if useJobProfilePhoto then @get('jobProfile')?.photoURL else null
    photoURL ||= @get('photoURL')
    if photoURL
      prefix = if photoURL.search(/\?/) is -1 then '?' else '&'
      return "#{photoURL}#{prefix}s=#{size}" if photoURL.search('http') isnt -1  # legacy
      return "/file/#{photoURL}#{prefix}s=#{size}"
    return "/db/user/#{@id}/avatar?s=#{size}&employerPageAvatar=#{useEmployerPageAvatar}"

  getSlugOrID: -> @get('slug') or @get('_id')

  set: ->
    if arguments[0] is 'jobProfileApproved' and @get("jobProfileApproved") is false and not @get("jobProfileApprovedDate")
      @set "jobProfileApprovedDate", (new Date()).toISOString()
    super arguments...

  @getUnconflictedName: (name, done) ->
    $.ajax "/auth/name/#{name}",
      success: (data) -> done data.name
      statusCode: 409: (data) ->
        response = JSON.parse data.responseText
        done response.name

  getEnabledEmails: ->
    (emailName for emailName, emailDoc of @get('emails', true) when emailDoc.enabled)

  setEmailSubscription: (name, enabled) ->
    newSubs = _.clone(@get('emails')) or {}
    (newSubs[name] ?= {}).enabled = enabled
    @set 'emails', newSubs

  isEmailSubscriptionEnabled: (name) -> (@get('emails') or {})[name]?.enabled

  a = 5
  b = 100
  c = b

  # y = a * ln(1/b * (x + c)) + 1
  @levelFromExp: (xp) ->
    if xp > 0 then Math.floor(a * Math.log((1/b) * (xp + c))) + 1 else 1

  # x = b * e^((y-1)/a) - c
  @expForLevel: (level) ->
    if level > 1 then Math.ceil Math.exp((level - 1)/ a) * b - c else 0

  level: ->
    User.levelFromExp(@get('points'))

  gems: ->
    gemsEarned = @get('earned')?.gems ? 0
    purchased = @get('purchased') ? {}
    gemsPurchased = purchased.gems ? 0
    sum = (arr) -> arr?.reduce((a, b) -> a + b) ? 0
    gemsSpent = sum(purchased.heroes) + sum(purchased.items) + sum(purchased.levels)
    gemsEarned + gemsPurchased - gemsSpent

  earnedHero: (heroOriginal) -> heroOriginal in (me.get('earned')?.heroes ? [])
  earnedItem: (itemOriginal) -> itemOriginal in (me.get('earned')?.items ? [])
  earnedLevel: (levelOriginal) -> levelOriginal in (me.get('earned')?.levels ? [])

  getBranchingGroup: ->
    return @branchingGroup if @branchingGroup
    group = me.get('testGroupNumber') % 4
    @branchingGroup = switch group
      when 0 then 'no-practice'
      when 1 then 'all-practice'
      when 2 then 'choice-explicit'
      when 3 then 'choice-implicit'
    @branchingGroup = 'choice-explicit' if me.isAdmin()
    application.tracker.identify branchingGroup: @branchingGroup
    @branchingGroup
