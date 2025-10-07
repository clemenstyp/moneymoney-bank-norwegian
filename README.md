# MoneyMoney Bank Norwegian extension

This is an extension for [MoneyMoney.app](http://moneymoney-app.com) to be used with accounts from the [Bank Norwegian](https://www.banknorwegian.de). It has only been tested with my private account, but it should probably work with other accounts too. The german phonenumber prefix (+49) is hardcoded in the script. 

## Installation

- Open the _Help_ menu in MoneyMoney
- Click on _Show Database in Finder_
- Drop `bank_norwegian.lua` from the git repo into the `Extensions` directory

## Account setup

- Open the _Account_ menu
- Click _Add account..._
- Select _Other_
- Select the __Bank Norwegian__ entry near the end of the drop-down list
- Fill in your _phonenumber_ (without leading zero) as username and _birthdate_ as password (for example: username: 1718885533 - password: 24121980)

From now on, every refresh will fetch new transactions which will be showed in the transaction overview for the respective account.
