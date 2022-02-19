# TODO: better isolate global `window.app`

# Base type behaviors for display system
# each `camera` gets added to stage
# each `object` gets added to all cameras
# each `hud` gets added to stage
# each `component` gets added to parent object
module.exports = DisplaySystem = (game) ->
  window.screenWidth = 640
  window.screenHeight = 360

  cameraMap = new Map
  cameras = []
  huds = {}

  Object.assign PIXI.settings,
    SCALE_MODE: PIXI.SCALE_MODES.NEAREST

  window.app = app = new PIXI.Application
    width: screenWidth
    height: screenHeight
    backgroundColor: 0x323C39

  # Take more control of render step
  app._ticker.remove(app.render, app)

  adjustResolution = ->
    res = floor min window.innerWidth / screenWidth, window.innerHeight / screenHeight
    renderer = app.renderer

    renderer.plugins.interaction.resolution = renderer.resolution = res
    renderer.resize(screenWidth, screenHeight)

  window.addEventListener "resize", adjustResolution
  adjustResolution()

  # Fullscreen
  document.addEventListener "keydown", (e) ->
    {key} = e
    if key is "F11"
      e.preventDefault()
      if document.fullscreenElement
        document.exitFullscreen()
      else
        app.view.requestFullscreen()

  addObjectToCamera = (e, behavior, camera) ->
    behavior.create?(e)
    displayObject = behavior.display(e)
    displayObject.entity = e
    displayObject.EID = e.ID

    camera.viewport.addChild displayObject
    camera.entityMap.set e.ID, displayObject

  addComponentToCamera = (e, behavior, name, camera) ->
    behavior.create?(e)
    displayObject = behavior.display(e)
    displayObject.entity = e
    displayObject.EID = e.ID
    displayObject.name = name

    parent = camera.entityMap.get e.ID
    parent.addChild displayObject

  # If a camera is added after there are displayable objects then each of those
  # objects needs to be added to the camera
  addEntitiesToCamera = (entities, camera) ->
    j = 0
    while e = entities[j++]
      {behaviors} = e
      i = 0
      while b = behaviors[i++]
        if b._system is self
          {name, type} = b

          if type is 'object'
            addObjectToCamera(e, b, camera)
          else if type is 'component'
            addComponentToCamera(e, b, name, camera)

  self =
    name: "display"
    camera:
      create: (e, behavior) ->
        behavior.create?(e)
        camera = behavior.display(e)
        camera.entity = e
  
        camera.entityMap = new Map
        cameraMap.set e.ID, camera
        cameras.push camera

        # TODO: remove reference to global game object!
        addEntitiesToCamera game.entities, camera

        app.stage.addChild camera

      render: (e, behavior) ->
        camera = cameraMap.get e.ID
        behavior.render(e, camera)

      destroy: (e) ->
        cameraMap.get(e.ID).destroy
          children: true
        cameraMap.delete e.ID
        cameras = Array.from cameraMap.values()
  
    # A component of another display object
    component:
      create: (e, behavior, name) ->
        cameras.forEach (camera) ->
          addComponentToCamera(e, behavior, name, camera)
  
      render: (e, behavior, name) ->
        cameras.forEach (camera) ->
          parent = camera.entityMap.get e.ID
  
          behavior.render e, parent.getChildByName(name)
  
      destroy: -> # Handled by parent

    object:
      create: (e, behavior) ->
        cameras.forEach (camera) ->
          addObjectToCamera e, behavior, camera

      render: (e, behavior) ->
        cameras.forEach (camera) ->
          displayObject = camera.entityMap.get(e.ID)
          behavior.render e, displayObject
  
      destroy: (e) ->
        cameras.forEach (camera) ->
          if displayObject = camera.entityMap.get(e.ID)
            camera.entityMap.delete(e.ID)
            if !displayObject.destroyed
              displayObject.destroy
                children: true
  
    hud:
      create: (e, behavior, name) ->
        key = "#{name}:#{e.ID}"
        behavior.create?(e)
        hud = behavior.display(e)
        hud.EID = e.ID
  
        huds[key] = hud
        app.stage.addChild hud
  
      render: (e, behavior, name) ->
        key = "#{name}:#{e.ID}"
        hud = huds[key]
        behavior.render(e, hud)
  
      destroy: (e, behavior, name) ->
        behavior.destroy?(e)
        key = "#{name}:#{e.ID}"
        huds[key].destroy
          children: true
        delete huds[key]

    createEntity: (e) ->
      {behaviors} = e
      i = 0
      while b = behaviors[i++]
        if b._system is self
          {name, type} = b
          self[type].create(e, b, name)
  
    updateEntity: noop
  
    destroyEntity: (e) ->
      {behaviors} = e
      i = 0
      while b = behaviors[i++]
        if b._system is self
          {name, type} = b
          self[type].destroy(e, b, name)
  
    # When engine is created/initialized
    create: ({behaviors}) ->
      Object.values(behaviors).forEach (b) ->
        # Annotate display behaviors with type and name
        if b._system is self
          [_, type, name] = b._tag.split ":"
          b.type = type
          b.name = name
  
    # game.update
    update: noop
  
    # When engine is destroyed / reset
    destroy: ->
      cameras.forEach (camera) ->
        camera.destroy
          children: true
      cameraMap.clear()
      cameras.length = 0
  
      Object.values(huds).forEach (hud) ->
        hud.destroy
          children: true
      huds = {}
  
    # When game.render is called
    render: ({entities}) ->
      i = 0
      while e = entities[i++]
        {behaviors} = e
        j = 0
        while b = behaviors[j++]
          if b.display
            {name, type} = b
            self[type].render(e, b, name)
  
      app.renderer.render(app.stage)

  return self
