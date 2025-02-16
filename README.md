# PunditExtraExtra

[![Gem Version](https://badge.fury.io/rb/pundit_extra.svg)](https://badge.fury.io/rb/pundit_extra)
[![Build Status](https://github.com/DannyBen/pundit_extra/workflows/Test/badge.svg)](https://github.com/DannyBen/pundit_extra/actions?query=workflow%3ATest)
[![Maintainability](https://api.codeclimate.com/v1/badges/61990b2b88d45ea6c89d/maintainability)](https://codeclimate.com/github/DannyBen/pundit_extra/maintainability)

---

This library borrows functionality from [CanCan(Can)][2] and adds it to [Pundit][1].

- `can?` and `cannot?` view helpers
- `load_resource`, `authorize_resource`, `load_and_authorize_resource` and 
  `skip_authorization` controller filters

The design intentions were:

1. To ease the transition from CanCanCan to Pundit.
2. To reduce boilerplate code in controller methods.
3. To keep things simple and intentionally avoid dealing with edge cases or
   endless magical options you need to memorize.

---

## Install

Add to your Gemfile:

```
gem 'pundit_extra'
```

Add to your `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include PunditExtraExtra
end
```


## View Helpers:  `can?` and `cannot?` 

You can use the convenience methods `can?` and `cannot?` in any controller 
and view.

- `if can? :assign, @task` is the same as Pundit's `policy(@task).assign?`
- `if can? :index, Task` is the same as Pundit's `policy(Task).index?`
- `if cannot? :assign, @task` is the opposite of `can?`


## Autoload and Authorize Resource

You can add these to your controllers to automatically load the resource 
and/or authorize it. 

```ruby
class TasksController < ApplicationController
  before_action :authenticate_user!
  load_resource except: [:index, :create]
  authorize_resource except: [:create]
end
```

The `load_resource` filter will create the appropriate instance variable 
based on the current action.

The `authorize_resource` filter will call Pundit's `authorize @model` in each
action.

You can use `except: :action`, or `only: :action` to limit the filter to a 
given action or an array of actions.

Example:

```ruby
class TasksController < ApplicationController
  before_action :authenticate_user!
  load_resource except: [:edit, :complete]
  authorize_resource except: :index

  def index
    # this happens automatically
    # @tasks = policy_scope(Task)
  end

  def show
    # this happens automatically
    # @task = Task.find params[:id]
    # authorize @task
  end

  def new
    # this happens automatically
    # @task = Task.new
    # authorize @task
  end

  def create
    # this happens automatically
    # @task = Task.new task_params
    # authorize @task
  end

end
```

In addition, you can use:

- `load_and_authorize_resource` which is a combination shortcut for 
  `load_resource` and `authorize_resource`
- `skip_authorization` which sends `skip_authorization` and 
  `skip_policy_scope` to Pundit for all (or the specified) actions.

## Credits

- [Jonas Nicklas](https://github.com/jnicklas) @ [Pundit][1]
- [Bryan Rite](https://github.com/bryanrite), [Ryan Bates](https://github.com/ryanb), [Richard Wilson](https://github.com/Senjai) @ [CanCanCan][2]
- [Tom Morgan](https://github.com/seven1m)

Thanks for building awesome stuff.

---

[1]: https://github.com/elabs/pundit
[2]: https://github.com/CanCanCommunity/cancancan
