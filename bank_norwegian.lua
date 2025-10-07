-- The MIT License (MIT)
--
-- Copyright (c) Clemens Eyhoff
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
--
--


WebBanking{
    version = 1.00,
    url         = "https://www.banknorwegian.de/login/",
    services    = {"Bank Norwegian"},
    description = "Bank Norwegian Web-Scraping"
}

-------------------------------------------------------------------------------
-- Helper functions
-------------------------------------------------------------------------------

-- convert iso date string to date object
local function strToDate(isoString)
    if isoString then
        local year, month, day, hour, min, sec = isoString:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
        return os.time{year=tonumber(year), month=tonumber(month), day=tonumber(day), hour=tonumber(hour), min=tonumber(min), sec=tonumber(sec), isdst=false}
    else
        return nil
    end
end


-------------------------------------------------------------------------------
-- Scraping
-------------------------------------------------------------------------------

-- global variables to re-use a single connection and cache the entry page of the web banking portal
local connection
local overviewPage
local twoFactorPage


function SupportsBank (protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Bank Norwegian"
end

-- main function for dealing with two-factor-auth and getting transaction history
function InitializeSession2 (protocol, bankCode, step, credentials, interactive)
    if step == 1 then
        MM.printStatus("Connecting to Bank Norwegian")
        if interactive == false then
            return "2FA only works interactively, because the login will be locked by the bank after a couple of unsuccesful attempts"
        end

        local mobilePhonePrefix = "+49 (0)"
        local regionId = "DE"
        local phoneNumber = credentials[1]
        local birthDate = credentials[2]

        connection = Connection()

        local loginSelectPage = HTML(connection:get(url))
        local currentUrl = connection:getBaseURL()

        local scheme, host = currentUrl:match("^([a-z][a-z0-9+.-]*)://([^/]+)")
        local baseUrl = "https://identity.banknorwegian.de"
        if scheme and host then 
            baseUrl =  scheme .. "://" .. host
        end

        local hmobileIdUrlHref  = loginSelectPage:xpath("//a[@data-method='MobileID']/@href"):get(1):text()
        local mobileIdUrl  = baseUrl .. hmobileIdUrlHref


        local loginPage = HTML(connection:get(mobileIdUrl))

        loginPage:xpath("//input[@id='MobilePhonePrefix']"):attr("value", mobilePhonePrefix)
        loginPage:xpath("//input[@id='RegionId']"):attr("value", regionId)
        loginPage:xpath("//input[@id='PhoneNumber']"):attr("value", phoneNumber)
        loginPage:xpath("//input[@id='BirthDate']"):attr("value", birthDate)

        local loginForm = loginPage:xpath("//form"):get(1)
        local loginResponsePage = HTML(connection:request(loginForm:submit()))

        local errorMessage = loginResponsePage:xpath("//*[@id='alerts-placeholder']"):text()
        if string.len(errorMessage) > 0 then
            MM.printStatus("Login failed. Reason: " .. errorMessage)
            return "Error received from Bank Norwegian banking: " .. errorMessage
        end
        
        MM.printStatus("Authentification in Bank Norwegian App needed")
        
        local mobildId2PollUrl  = baseUrl .. "/MyPage/MobileId2Poll"
        local mobildId2DoneUrl  = baseUrl .. "/MyPage/MobileId2Done"
        
        for i = 1, 60 do
            MM.sleep(10)
            local pollStatus = connection:get(mobildId2PollUrl)
            local pollStatusDict =  JSON(pollStatus):dictionary()
            local status = pollStatusDict['status']
            -- MM.printStatus("Authentification in Bank Norwegian App needed \nPollStatus: " .. status)
            if status == "COMPLETED" then
                local mobileIdDone = HTML(connection:get(mobildId2DoneUrl))
                local mobileIdDoneForm = mobileIdDone:xpath("//form"):get(1)
                local mobileIdDoneResponsePage = HTML(connection:request(mobileIdDoneForm:submit()))

                overviewPage = mobileIdDoneResponsePage
                MM.printStatus("Login successful");
                return nil 
            elseif status == "TIMEOUT" then
                return "Timeout for authentication: " .. tostring(pollStatus)
            end
            
        end
    end
    return LoginFailed
end    

function ListAccounts (knownAccounts)
    baseUrl = "https://www.banknorwegian.de"

    local creditcardData = JSON(connection:get(baseUrl .. "/api/mypage/creditcard/", "", "", {Accept = "application/json"})):dictionary()
    local creditcardOverviewApiUrl = creditcardData['apiPathCreditCardOverview'] or "/api/mypage/creditcard/overview"
    local creditcardOverviewData = JSON(connection:get(baseUrl .. creditcardOverviewApiUrl, "", "", {Accept = "application/json"})):dictionary()

    local accounts = {}
    for i, creditcard in ipairs(creditcardOverviewData['creditCardList']) do
        if creditcard['isActive'] or false then
            local account = {
                name = creditcard['cardNumberMasked'] or creditcard['id'] or 'unknown',
                accountNumber = creditcard['accountNumber'] or 'unknown',
                bic = 'NORWNOK1',
                owner = creditcard['cardholderName'] or 'unknown',
                iban = creditcard['accountNumber'] or 'unknown',
                currency = "EUR",
                type = AccountTypeCreditCard
            }

            table.insert(accounts, account)  
        end
    end

    return accounts
end

function RefreshAccount (account, since)
    baseUrl = "https://www.banknorwegian.de"
    
    local sinceString = ""
    if since then
        sinceString = os.date("%Y-%m-%d", since)
    end
    local transactionApiUrl = string.format("/api/v1/transaction/GetTransactionsFromTo?accountNo=%s&getLastDays=true&fromLastEOC=false&dateFrom=%s&dateTo=&coreDown=false", account['accountNumber'],  sinceString)
    
    local transactionsData = JSON(connection:get(baseUrl .. transactionApiUrl, "", "", {Accept = "application/json"})):dictionary()

    local transactions = {}
    for i, aTransaction in ipairs(transactionsData) do
        local transaction = {
            name = aTransaction['merchantName'],
            accountNumber = aTransaction['foreignAccountNo'],
            -- bankCode = aTransaction['merchantName'],
            amount = aTransaction['currencyAmount'],
            currency = aTransaction['currencyCode'],
            bookingDate = strToDate(aTransaction['transactionDate']),
            valueDate = strToDate(aTransaction['valueDate']),
            purpose = aTransaction['message'],
            transactionCode = aTransaction['bnTransactionTypeID'],
            -- textKeyExtension = aTransaction['merchantName'],
            -- purposeCode = aTransaction['transactionTypeText'],
            -- bookingKey = aTransaction['merchantName'],
            bookingText = aTransaction['transactionTypeText'],
            -- primanotaNumber = aTransaction['merchantName'],
            -- batchReference = aTransaction['merchantName'],
            endToEndReference = aTransaction['reference'],
            -- mandateReference = aTransaction['merchantName'],
            creditorId = aTransaction['mccName'],
            -- returnReason = aTransaction['merchantName'],
            booked = aTransaction['isBooked'],
        }
        table.insert(transactions, transaction)
    end

    local creditcardData = JSON(connection:get(baseUrl .. "/api/mypage/creditcard/", "", "", {Accept = "application/json"})):dictionary()
    local balance = creditcardData['balance']


    return {balance=balance, transactions=transactions}
end

function EndSession ()
    baseUrl = "https://www.banknorwegian.de"
    local logoutPage = HTML(connection:get(baseUrl .. "/home/logout/"))
end