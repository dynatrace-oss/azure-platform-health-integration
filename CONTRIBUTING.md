# How to Contribute

We'd love to accept your patches and contributions to this project. There are
just a few small guidelines you need to follow.

## Found a bug?

If you find a bug/issue in the source code or a mistake in the documentation,
you can help us by
[creating an issue](https://github.com/dynatrace-oss/azure-platform-health-integration/issues/new)
here on GitHub. Please provide an issue reproduction. Screenshots are also
helpful.

You can help the team even more and submit a pull request with a fix.

## Want a feature?

You can request a new feature also by
[creating an issue](https://github.com/dynatrace-oss/azure-platform-health-integration/issues/new).

## Submitting a pull request

Before you submit your pull request (PR) consider the following guidelines:

- Search GitHub for an open or closed issue or PR that relates to your
  submission.
- Fork azure-platform-health-integration into your namespace by using the fork button on github.
- Make your changes in a new git branch: `git checkout -b my-fix-branch master`
- Create your patch/fix/feature.
- Commit your changes using a descriptive commit message.
- Before pushing to Github make sure that `az bicep build --file ./src/azure-health-integration.bicep` runs successfully and that your changes successfully deploy to your azure environment. 
- Push your branch to GitHub.
- Create a new pull request from your branch against the azure-platform-health-integration:master
  branch.
- If we suggest changes then:
  - Make the required updates.
  - Make sure that `az bicep build --file ./src/azure-health-integration.bicep` runs successfully.
  - Make sure your branch is up-to-date and includes the latest changes on master

## Contributor License Agreement

Contributions to this project must be accompanied by a Contributor License
Agreement. You (or your employer) retain the copyright to your contribution;
this simply gives us permission to use and redistribute your contributions as
part of the project.

You generally only need to submit a CLA once, so if you've already submitted one
(even if it was for a different project), you probably don't need to do it
again.

## Code Reviews

All submissions, including submissions by project members, require review. We
use GitHub pull requests for this purpose. Consult
[GitHub Help](https://help.github.com/articles/about-pull-requests/) for more
information on using pull requests.

