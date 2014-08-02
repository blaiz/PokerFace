###

pokerface-server
https://github.com//pokerface-server

Copyright (c) 2014 
Licensed under the GNU GPLv3 license.

###

'use strict'

exports.server = ->
  io = require("socket.io").listen(process.env.PORT || 9001)
  console.log "Listening on port ", process.env.PORT || 9001
  require('webrtc.io').listen 9002
  poker = require "node-poker"
  cookie = require "cookie"

  clients = {} # contains a list of socket objects, one for each client
  clientDisconnectTimeouts = {} # list of potential timeoutObjects to cancel player disconnection if player comes back online
  players = [] # contains an array of playerId to match poker player with socket clients
  table = null # our master table object
  playerIdCount = lastBet = 0

  io.sockets.on "connection", (socket) ->
    # if this is the first client, let's create a table
    # this doesn't start the game yet
    if playerIdCount is 0
      table = new poker.Table 1, 2, 2, 10, 200, 200
      
    playerId = cookie.parse(socket.request.headers.cookie).playerId if socket.request.headers.cookie?

    # if this is a new client, add it to the list of clients, and create a player Object for them
    if not playerId? or not clients[playerId]?
      playerId = playerIdCount
      players.push playerId
      table.AddPlayer playerId, playerIdCount, "No Name", 200
      playerIdCount++
    else if clientDisconnectTimeouts[playerId]?
      console.log "Cancelling disconnection of player # ", playerId
      clearTimeout clientDisconnectTimeouts[playerId]
      delete clientDisconnectTimeouts[playerId]

    clients[playerId] = {socket, playerId}
    playerId = clients[playerId].playerId
    socket.emit "setPlayerId", clients[playerId].playerId

    # if player joins after the game has started, let's send them their hand now
    if table.game?
      socket.emit "addHand", table.players[clients[playerId].playerId].cards

    sendState table

    socket.on "startGame", ->
      # start the game
      table.StartGame()
      # give each player their hand
      for key, client of clients
        client.socket.emit "addHand", table.players[client.playerId].cards
      sendState table

    socket.on "fold", ->
      table.players[playerId].Fold()
      sendState table

    socket.on "bet", (amount) ->
      # check is a bet of 0
      if amount is 0
        table.players[playerId].Check()
        # all in is a bet of all chips
      else if amount is table.players[playerId].chips
        table.players[playerId].AllIn()
        # call is a bet the same amount as the last bet
      else if amount is lastBet
        table.players[playerId].Call()
        # betting more than last time (bet or raise)
      else
        table.players[playerId].Bet amount
        lastBet = amount
      sendState table

    socket.on "showHand", ->
      # a player decided to show their hand, let's send their hand to everyone
      for key, client of clients
        client.socket.emit "showHand", {
          playerId,
          cards: table.players[playerId].cards
        }

    socket.on "removePlayer", ->
      console.log "Setting timeout to remove player ", playerId, " in 10 seconds"
      clientDisconnectTimeouts[playerId] = setTimeout ->
        console.log "Removing player # ", playerId, " now"
        table.players.splice playerId, 1 # @todo handle properly
        sendState table
      , 10000

    socket.on "renamePlayer", (name) ->
      table.players[playerId].playerName = name
      sendState table

  ###
    Get a state (table) object and turn it into a JSON string
    We have to do all that logic because of circular references
    Otherwise, JSON.stringify throws exceptions
  ###
  toJSONState = (state) ->
    cache = []
    state = JSON.stringify state, (key, value) ->
      if typeof value is "object" and value isnt null

        # Circular reference found, discard key
        return if cache.indexOf(value) isnt -1

        # Store value in our collection
        cache.push value
      value
    cache = null
    # we need to remove hands and the deck from the state,
    # so we're making it an object again, clean it up, then turn it back into a string
    removeCardsFromState(JSON.parse(state))

  ###
    Remove all players' hands and the deck from a state
  ###
  removeCardsFromState = (state) ->
    for player in state.players
      delete player.cards
    delete state.game?.deck
    return state

  ###
    Send the state to all clients to keep them in sync with the internal state of our application
  ###
  sendState = (state) ->
    for id, client of clients
      client.socket.emit "updateState", toJSONState state
