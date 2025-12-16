# Version Control

The version control editor is a way to sync your scripts in Roblox Studio with a GitHub repo via Jexplorer.

There are 2 dropdowns, Tokens and Repos.

## The Tokens Dropdown

The tokens dropdown is where you store your [github fine-grained personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#fine-grained-personal-access-tokens) to your repos.

To create a new token, simply click the "+" button in the header of the dropdown and edit your tokens name and value.

Each repository should ideally have its own fine-grained token stored in here, though 1 universal token is also an option.

To use a token for all actions done via the version control widget, simply click the cursor button in your token, next to the delete button which has a "-" symbol. This will highlight the button blue and that indicates your token is being equipped

Once you've equipped a token, you can perform actions such as push, pull, etc in the Repos dropdown.

## The Repos Dropdown

The repos dropdown is where you store your individual GitHub repository proxies.
To create a new repo proxy, simply click the "+" button in the dropdown's header and select the root instance for the source of your repo.

This will create a new repo proxy dropdown which you can expand to reveal several options, these being:

- Root: Instance
- RepoId: string (your-user-name/your-repo-name)
- Branch: string (default: main)
- Path: string (the path you wanna push to/pull from, default: src)
- Push: Dropdown
    - CommitMsg: string (the commit message you wanna use for the push)
    - PushOverwrite: Button (pushes to the repo's source and overwrites existing contents with the new one inside the root instance)
    - PushUpdate: Button (pushes to the repo's source and updates existing contents with the new one inside the root instance)
- RevertLastCommit: Button (reverts the last commit made to the branch)
- Pull: Button (pulls the contents of the repo's source into your root instance)

RepoId and CommitMsg are really the only ones you usually need to edit, though if you wanna change the root instance you can click, drag and drop the Root value to select a new one, similar to how you select Instance type properties in Roblox's Properties widget.