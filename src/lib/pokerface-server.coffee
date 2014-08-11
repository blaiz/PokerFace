###

pokerface-server
https://github.com//pokerface-server

Copyright (c) 2014 
Licensed under the GNU GPLv3 license.

###

'use strict'

exports.server = ->
  pokerEngine = require "node-poker"

  app = require("express")()
  io = require("socket.io").listen 10001
  require('webrtc.io').listen 10002
  cors = require "cors"

  app.use cors()

  app.listen process.env.PORT || 10000
  console.log "Listening on port ", process.env.PORT || 10000

  app.post "/gameroom", (req, res) ->
    uid = generateUID() while gameRooms.hasOwnProperty(uid) # make sure we generate a uid not already being used
    res.json
      id: generateUID()

  # from http://stackoverflow.com/a/6248722
  generateUID = ->
    ("0000" + (Math.random()*Math.pow(36,4) << 0).toString(36)).slice(-4)

  gameRooms = {}
  clientDisconnectTimeouts = {} # list of potential timeoutObjects to cancel player disconnection if player comes back online
    
  io.of("/gameroom").on "connection", (socket) ->
    console.info "New client connected with ID ", socket.id
    gameRoomId = null
    gameRoom = {}
    playerID = null
    
    socket.on "joinGameRoom", (IDs) ->
      {gameRoomId, playerId} = IDs
      socket.join gameRoomId

      if gameRoomId of gameRooms
        gameRoom = gameRooms[gameRoomId]
      else
        # when the first player joins all variables need to be initialized
        gameRooms[gameRoomId] = gameRoom =
          clients: {} # contains a list of socket objects, one for each client
          table: new pokerEngine.Table 1, 2, 2, 10, 200, 200 # our master table object; this doesn't start the game yet
          lastBet: 0

      playerID = playerId
  
      # if this is a new client, add it to the list of clients, and create a player Object for them
      if not playerID? or not gameRoom.clients[playerID]?
        playerID = gameRoom.table.players.length
        gameRoom.table.AddPlayer playerID, playerID, "No Name", 200
      else if clientDisconnectTimeouts[playerID]?
        console.log "Cancelling disconnection of player # ", playerID
        clearTimeout clientDisconnectTimeouts[playerID]
        delete clientDisconnectTimeouts[playerID]

      gameRoom.clients[playerID] = {socket, gameRoomId, playerID}
      socket.emit "setPlayerId", playerID
  
      # if player joins after the game has started, let's send them their hand now
      if gameRoom.table.game?
        socket.emit "addHand", gameRoom.table.players[playerID].cards
  
      sendState gameRoom.table, gameRoomId

    socket.on "startGame", ->
      # start the game
      gameRoom.table.StartGame()
      # give each player their hand
      for key, client of gameRoom.clients
        client.socket.emit "addHand", gameRoom.table.players[client.playerID].cards
      sendState gameRoom.table, gameRoomId

    socket.on "fold", ->
      gameRoom.table.players[playerID].Fold()
      sendState gameRoom.table, gameRoomId

    socket.on "bet", (amount) ->
      amount = parseInt amount, 10
      # check is a bet of 0
      if amount is 0
        gameRoom.table.players[playerID].Check()
        # all in is a bet of all chips
      else if amount is gameRoom.table.players[playerID].chips
        gameRoom.table.players[playerID].AllIn()
        # call is a bet the same amount as the last bet
      else if amount is gameRoom.lastBet
        gameRoom.table.players[playerID].Call()
        # betting more than last time (bet or raise)
      else
        gameRoom.table.players[playerID].Bet amount
        gameRoom.lastBet = amount
      sendState gameRoom.table, gameRoomId

    socket.on "showHand", ->
      # a player decided to show their hand, let's send their hand to everyone
      for key, client of gameRoom.clients
        client.socket.emit "showHand", {
          playerID,
          cards: gameRoom.table.players[playerID].cards
        }

    socket.on "renamePlayer", (name) ->
      gameRoom.table.players[playerID].playerName = name
      sendState gameRoom.table, gameRoomId

    socket.on "disconnect", ->
      return
      console.log "Setting timeout to remove player ", playerID, " in 10 seconds"
      clientDisconnectTimeouts[playerID] = setTimeout ->
        console.log "Removing player # ", playerID, " now"
        gameRoom.table.players.splice playerID, 1
        sendState gameRoom.table, gameRoomId
      , 10000

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
  sendState = (state, gameRoomId) ->
    io.of("/gameroom").in(gameRoomId).emit "updateState", toJSONState state
