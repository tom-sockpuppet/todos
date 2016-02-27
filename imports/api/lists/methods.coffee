{ ValidatedMethod } = require 'meteor/mdg:validated-method'
{ SimpleSchema } = require 'meteor/aldeed:simple-schema'
{ DDPRateLimiter } = require 'meteor/ddp-rate-limiter'
{ Lists } = require './lists.coffee'

LIST_ID_ONLY = new SimpleSchema
	listId:
		type: String
.validator()


module.exports.insert = new ValidatedMethod
  name: 'Lists.methods.insert'
  validate: new SimpleSchema({}).validator()
  run: ->
    Lists.insert {}


module.exports.makePrivate = new ValidatedMethod
  name: 'Lists.methods.makePrivate'
  validate: LIST_ID_ONLY
  run: ({ listId }) ->
    unless @userId?
      throw new Meteor.Error 'Lists.methods.makePrivate.notLoggedIn', 'Must be logged in to make private lists.'

    list = Lists.findOne listId

    if list.isLastPublicList()
      throw new Meteor.Error 'Lists.methods.makePrivate.lastPublicList', 'Cannot make the last public list private.'

    Lists.update listId,
    	$set:
    		userId: @userId


module.exports.makePublic = new ValidatedMethod
  name: 'Lists.methods.makePublic'
  validate: LIST_ID_ONLY
  run: ({ listId }) ->
    unless @userId?
      throw new Meteor.Error 'Lists.methods.makePublic.notLoggedIn', 'Must be logged in.'
    list = Lists.findOne listId

    unless list.editableBy @userId
      throw new Meteor.Error 'Lists.methods.makePublic.accessDenied', 'You don\'t have permission to edit this list.'

    # XXX the security check above is not atomic, so in theory a race condition could
    # result in exposing private data
    Lists.update listId,
    	$unset:
    		userId: yes


module.exports.updateName = new ValidatedMethod
  name: 'Lists.methods.updateName'
  validate: new SimpleSchema(
    listId: type: String
    newName: type: String).validator()
  run: ({ listId, newName }) ->
    list = Lists.findOne listId

    unless list.editableBy @userId
      throw new Meteor.Error 'Lists.methods.updateName.accessDenied', 'You don\'t have permission to edit this list.'

    # XXX the security check above is not atomic, so in theory a race condition could
    # result in exposing private data

    Lists.update listId,
    	$set:
    		name: newName


module.exports.remove = new ValidatedMethod
  name: 'Lists.methods.remove'
  validate: LIST_ID_ONLY
  run: ({ listId }) ->
    list = Lists.findOne listId

    unless list.editableBy @userId
      throw new Meteor.Error 'Lists.methods.remove.accessDenied', 'You don\'t have permission to remove this list.'

    # XXX the security check above is not atomic, so in theory a race condition could
    # result in exposing private data

    if list.isLastPublicList()
      throw new Meteor.Error 'Lists.methods.remove.lastPublicList', 'Cannot delete the last public list.'

    Lists.remove listId


# Get list of all method names on Lists
LISTS_METHODS = _.pluck [
  module.exports.insert
  module.exports.makePublic
  module.exports.makePrivate
  module.exports.updateName
  module.exports.remove
], 'name'

if Meteor.isServer
  # Only allow 5 list operations per connection per second
  DDPRateLimiter.addRule
    name: (name) ->
      _.contains LISTS_METHODS, name

    # Rate limit per connection ID
    connectionId: ->
      yes

  , 5, 1000