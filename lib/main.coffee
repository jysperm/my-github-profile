{CompositeDisposable} = require 'atom'
{View} = require 'space-pen'
request = null
_ = null
Q = null

class StatusBarView extends View
  @content: ->
    @a href: '#', class: 'inline-block', click: 'onClick', 'Loading...'

  initialize: (statusBar) ->
    @detail = 'Loading...'
    @tile = statusBar.addRightTile
      priority: 0
      item: @

  setProfile: (@profile) ->
    type = atom.config.get 'my-github-profile.statusbarNumber'

    if type == 'notifications'
      if @profile.notifications.length > 0
        @text "#{@profile.login}: #{@profile.notifications.length}"
      else if @profile.notifications
        @text "#{@profile.login}"
      else if !atom.config.get('my-github-profile.githubToken')
        @text 'Need personal access tokens'
    else
      @text "#{@profile.login}: #{@profile.followers}"

    total_repos = @profile.public_repos + (@profile.owned_private_repos ? 0)

    @detail = """
      Username: #{@profile.login}
      Followers: #{@profile.followers}
      Repos: #{total_repos}
    """

    if @profile.repos
      total_stargazers = _.sum @profile.repos, 'stargazers_count'
      @detail += "\nTotal stars: #{total_stargazers}"

    if @profile.events
      commits = _.flatten _.where(@profile.events, type: 'PushEvent').map ({repo, payload}) ->
        return payload.commits.map ({sha}) ->
          return {
            repo_name: repo.name
            commit_sha: sha
          }

      @detail += "\nRecent commits: #{commits.length}"

      most_repos = _(commits).groupBy('repo_name').mapValues( (commits) ->
        return {
          repo_name: commits[0].repo_name
          commits: commits.length
        }
      ).values().sortBy('commits').value()

      @detail += "\nRecently working on: #{_.last(most_repos).repo_name}"

    if @profile.notifications
      @detail += "\nUnread notifications: #{@profile.notifications.length}"

  onClick: ->
    atom.notifications.addSuccess 'My GitHub Profile',
      detail: @detail

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
    refreshTimeout:
      title: 'Refresh Interval (seconds)'
      type: 'number'
      default: 1800
    statusbarNumber:
      title: 'Show in statusbar'
      type: 'string'
      default: 'followers'
      enum: ['notifications', 'followers']

  package: require '../package'

  activate: ->
    @disposables = new CompositeDisposable()

    @disposables.add atom.commands.add 'atom-workspace',
      'my-github-profile:refresh': => @refresh()

    setTimeout @refresh.bind(@), 1000
    setInterval @refresh.bind(@), 1000 * atom.config.get('my-github-profile.refreshTimeout')

  deactivate: ->
    @disposables.dispose()
    @statusBarView.destroy()

  serialize: ->

  refresh: ->
    request ?= require 'request'
    _ ?= require 'lodash'
    Q ?= require 'q'

    console.log '[my-github-profile] refreshing info...'

    @githubUsername = atom.config.get 'my-github-profile.githubUsername'
    @githubToken = atom.config.get 'my-github-profile.githubToken'

    @githubAPI("/users/#{@githubUsername}").done (profile) =>
      setProfile = (result) =>
        @statusBarView?.setProfile _.extend profile, result

      @githubAPI("/users/#{@githubUsername}/repos").then (repos) ->
        setProfile repos: repos

      @githubAPI("/users/#{@githubUsername}/events?per_page=50").then (events) ->
        setProfile events: events

      if @githubToken
        @githubAPI('/notifications').then (notifications) ->
          setProfile notifications: notifications

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
