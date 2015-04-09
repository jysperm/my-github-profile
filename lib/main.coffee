{CompositeDisposable} = require 'atom'
request = require 'request'
{View} = require 'space-pen'
_ = require 'lodash'
Q = require 'q'

class StatusBarView extends View
  @content: ->
    @a href: '#', class: 'inline-block', click: 'onClick', 'Loading...'

  initialize: (statusBar) ->
    @tile = statusBar.addRightTile
      priority: 0
      item: @

  setProfile: (@profile) ->
    console.log profile

    @text "#{@profile.login}: #{@profile.followers}"

    @profile.total_repos = @profile.public_repos + (@profile.owned_private_repos ? 0)

  onClick: ->
    detail = """
      Username: #{@profile.login}
      Followers: #{@profile.followers}
      Repos: #{@profile.total_repos}
    """

    if @profile.notifications
      detail += "\nUnread notifications: #{@profile.notifications.length}"

    atom.notifications.addSuccess @profile.login,
      detail: detail

  destroy: ->
    @tile.destroy()

module.exports = MyGithubProfile =
  config:
    githubUsername:
      type: 'string'
      default: 'jysperm'
    githubToken:
      type: 'string'
      default: ''

  package: require '../package'

  activate: ->
    @githubUsername = atom.config.get 'my-github-profile.githubUsername'
    @githubToken = atom.config.get 'my-github-profile.githubToken'
    @disposables = new CompositeDisposable()

    @disposables.add atom.commands.add 'atom-workspace',
      'my-github-profile:refresh': => @refresh()

    @refresh()

  deactivate: ->
    @disposables.dispose()
    @statusBarView.destroy()

  serialize: ->

  refresh: ->
    @fetchProfile().done (profile) =>
      @statusBarView?.setProfile profile

      @fetchAdded(profile).done =>
        @statusBarView?.setProfile profile

  consumeStatusBar: (statusBar) ->
    @statusBarView = new StatusBarView statusBar

  githubAPI: (endpoint) ->
    if @githubToken
      url = "https://#{@githubUsername}:#{@githubToken}@api.github.com#{endpoint}"
    else
      url = "https://api.github.com#{endpoint}"

    Q.Promise (resolve, reject) =>
      request url,
        headers:
          'User-Agent': "#{@package.name}/#{@package.version}"
      , (err, res, body) ->
        if err
          reject err
        else
          resolve JSON.parse body

  fetchProfile: ->
    @githubAPI "/users/#{@githubUsername}"

  fetchAdded: (profile) ->
    Q.all [
      @githubAPI('/notifications').then (notifications) ->
        profile.notifications = notifications
    ]
