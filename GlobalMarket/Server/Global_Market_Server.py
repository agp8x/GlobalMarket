# -*- encoding: utf-8 -*-

import os
import sys
import logging
import sqlite3
import bencode
import configparser
import threading
from binascii import crc32
import time
import socket
import queue
import random
import math

if sys.version < 3:
	raise Exception("This program is to be used on python3.x")

log = logging.getLogger(__name__)


class GMServer(object):
	
	def __init__(self, arguments):
		self.__clients = dict()
		self.__started = False
		self.__sendQueue = queue.Queue()
		self.__recvSock = None
		self.__sendSock = None
		self.__storage = dict()
		self.__db = arguments.database
		self.__sem = threading.Semaphore()
		self.__cm = None
		self.__dm = None
		self.__sm = None
		self.__rm = None
		return
	
	@property
	def running(self):
		return self.__started
	
	def start(self):
		'''
		Starts the server and returns.
		The caller needs to keep the program alive!
		'''
		if self.__started:
			#Already running
			log.warn("Tried to start an already running server")
			return
		#start the db first
		self.__dm = threading.Thread(target=self.__databaseHandler)
		self.__dm.daemon = True
		self.__dm.start()
		#next is the sender
		self.__sm = threading.Thread(target=self.__sender)
		self.__sm.daemon = True
		self.__sm.start()
		#next comes the reciver
		self.__rm = threading.Thread(target=self.__reciver)
		self.__rm.daemon = True
		self.__rm.start()
		#last is the clientmanager
		self.__cm = threading.Thread(target=self.__clientManager)
		self.__cm.daemon = True
		self.__cm.start()
		log.info("Server started.")
		return
	
	def close(self):
		if not self.__started:
			return
		self.__started = False
		while self.__cm.is_alive() or self.__dm.is_alive() or self.__sm.is_alive() or self.__rm.is_alive():
			#One of the threads is still running
			continue
		self.__cm.join()
		self.__dm.join()
		self.__sm.join()
		self.__rm.join()
		log.info("GMServer stopped")
		return
	
	def __del__(self):
		self.close()
		return
	
	def __clientManager(self):
		#Manages the clientlist
		while self.__started:
			for x in self.__clients:
				if self.__clients[x] < time.time():
					#Timeout
					log.info("Client %s timed out" % x)
					self.__clients.pop(x)
			time.sleep(30)
		log.debug("ClientManager stopped")
		return
	
	def __reciver(self):
		#Recives and handles the packages
		log.info("Starting reciving")
		while self.__storage == {}:
			#Wait for db to finish
			time.sleep(0.1)
		while self.__started:
			#Keep in mind: http://support.microsoft.com/kb/822061/ !
			packet, address = self.__recvSock.recvfrom(8192)
			try:
				data = self.decodePacket(packet)
			except OSError as e:
				#Error on reading
				if not self.__started:
					#Server stopped, nothing serious
					continue
				else:
					log.exception(e)
					raise
			response = {
						"error": "",
						"continue": True,
						"data": {}
						}
			log.debug("New packet from %s: %s" % (address, data))
			#Check for errors first
			if data is None:
				#Send a NACK
				response['error'] = "Transmission Error"
			elif type(data) != dict:
				response['error'] = "Type Error"
			elif not 'user' in data or not 'uid' in data:
				#Missing keys
				response['error'] = "Missing user or uid"
				response['continue'] = False
			#From here on we got a (probably) valid packet
			elif data['request'] != 'register' and not address in self.__clients:
				#Unknown client wants to do something except registering...
				response['error'] = "Not registered"
				response['continue'] = False
			elif data['request'] == 'register':
				#User wants to register himself
				#Needed keys:
				# password
				# version
				if not 'password' in data and self.__password != "":
					#Missing password
					response['error'] = "Missing password"
					response['continue'] = False
				elif data['password'] != self.__password and self.__password != "":
					#Wrong password
					response['error'] = "Wrong password"
					response['continue'] = False
				elif not 'version' in data:
					response['error'] = "Missing version tag"
					response['continue'] = False
				elif data['version'] != __version__:
					response['error'] = "Wrong version. This server is running on version %s" % __version__
					response['continue'] = False
				else:
					#Client is registering
					#Add to clients and send full update
					self.__clients[address] = time.time() + 30
					response['data'] = self.__getFullUpdate()
			elif data['request'] == 'update':
				self.__clients[address] = time.time() + 30
				response['data'] = self.__getFullUpdate()
			elif data['request'] == 'buyorsell':
				#Client wants to buy or sell
				self.__clients[address] = time.time() + 30
				if not 'data' in data:
					#Missing buy or sell data...
					response['error'] = "Missing data"
				elif type(data['data']) != dict:
					#Invalid type...
					response['error'] = "Type Error"
				else:
					#Seems good for now, checking storage and sending response
					response['data'] = self.__storageCheck(data['data'])
					if response['data'] is None:
						response['error'] = "Missing key"
						response['continue'] = False
			elif data['request'] == 'nop':
				#Client doesn't want to do anything, just updating the timestamp
				self.__clients[address] = time.time() + 30
				#This is the only case we use continue in this loop inside a if check
				continue
			else:
				#Unknown packet
				response['error'] = "Unknown packet"
			self.__sendQueue.put([response, address])
			continue
		#Thread stopping
		log.info("Stopped reciving")
		return
	
	def __getFullUpdate(self):
		#For now just send the storage, maybe some changes later
		return self.__storage
	
	def __sender(self):
		log.info("Sender started")
		while self.__started:
			if self.__sendQueue.qsize() <= 0:
				#Nothing to send
				time.sleep(1)
			d = self.__sendQueue.get()
			packet = self.encodePacket(d[0])
			self.__sendSock.sendto(packet, d[1])
			continue
		#Stopped
		log.info("Sender stopped")
		return
	
					
				
			
	def __storageCheck(self, data):
		self.__sem.acquire()
		for key in data:
			if not 'amount' in data[key]:
				#Missing key
				self.__sem.release()
				return None
			if data[key]['amount'] == 0:
				#Empty, continue
				continue
			if not key in self.__storage and data[key]['amount'] < 0:
				#Tried to buy something we don't have...
				data[key]['amount'] = 0
				continue
			if not key in self.__storage:
				self.__storage[key] = dict()
				self.__storage[key]['price'] = 0
				self.__storage[key]['amount'] = 0
				#No continue here, it's just for the further checks
			if data[key]['amount'] < 0 and self.__storage[key]['amount']-data[key]['amount'] < 0:
				#Tried to buy more than in the storage
				data[key]['amount'] = self.__storage[key]['amount']*-1
				self.__storage[key]['amount'] = 0
				continue
			if data[key]['amount'] < 0:
				# += because the amount is already negative
				self.__storage[key]['amount'] += data[key]['amount']
				data[key]['amount'] = 0
			if data[key]['amount'] > 0:
				#Selling
				#No checks, the client can sell everything
				# Until the dbUpdate starts it won't have a price so the user has to handle with it...
				self.__storage[key]['amount'] += data[key]['amount']
				continue
		self.__sem.release()
		return data
			
	def __databaseHandler(self):
		db = sqlite3.connect(self.__db)
		cur = db.cursor()
		cur.execute('''CREATE TABLE IF NOT EXISTS `ServerStorage` (
						`id`	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
						`name`	TEXT NOT NULL UNIQUE,
						`amount`	INTEGER NOT NULL DEFAULT 0,
						`price`	INTEGER NOT NULL DEFAULT 1000,
						`modifier`	REAL NOT NULL DEFAULT 0.1,
						`min` INTEGER NOT NULL DEFAULT 10,
						`max` INTEGER NOT NULL DEFAULT 10000
						);''')
		db.commit()
		shutdown = False
		while self.__started or shutdown:
			cur.execute('''SELECT `name`, `amount`, `price`, `modifier`, `min`, `max` FROM `ServerStorage`''')
			#Get current database values
			dbVals = {}
			for entry in cur.fetchall():
				name, amount, price, modifier, min_, max_ = entry
				dbVals['name'] = {'amount':amount, 'price':price, 'modifier':modifier, 'min': min_, 'max': max_}
			if dbVals == self.__storage:
				log.debug("No change since last dbCheck")
			else:
				self.__sem.acquire()
				for key in self.__storage:
					if not key in dbVals:
						dbVals[key] = self.__storage[key]
						dbVals[key]['price'] = 0
						dbVals[key]['modifier'] = 0.1
						dbVals[key]['min'] = 10
						dbVals[key]['max'] = 10000 
					else:
						dbVals[key]['amount'] = self.__storage[key]['amount']
					dbVals[key]['amount'] += dbVals[key]['amount']*random.uniform(-1*dbVals[key]['modifier'], dbVals[key]['modifier'])
					dbVals[key]['amount'] = math.floor(dbVals[key]['amount'])
					#Not the correct way to calculate I know but it's faster
					price = dbVals[key]['max']-(dbVals[key]['max']/1e+010*dbVals[key]['amount'])+dbVals[key]['min']
					price += price*random.uniform(-1*dbVals[key]['modifier'], dbVals[key]['modifier'])
					dbVals[key]['price'] = math.floor(price)
				self.__storage = dbVals
				self.__sem.release()
				#Sadly executemany doesn't work with these statements and the design I use for the dict
				#Because of that I need to create a 2 temporary lists just for it...
				l = [(x, dbVals[x]['amount'], dbVals[x]['price']) for x in dbVals]
				m = [(dbVals[x]['amount'], dbVals[x]['price'], x) for x in dbVals]
				cur.executemany('''UPDATE `ServerStorage` SET `amount`=?, `price`=? WHERE `name`=?''', m)
				db.commit()
				cur.executemany('''INSERT OR IGNORE INTO `ServerStorage` (`name`, `amount`, `price`) VALUES (?,?,?)''', l)
				db.commit()
				#Cleanup...
				del(m)
				del(l)
			#Wait 10 minutes until next check
			if shutdown:
				#Was the last run...
				break
			to = 600
			while to > 0:
				#Busy wait because we need to check self.__started too
				if not self.__started:
					to = 0
					shutdown = True
					continue
				time.sleep(10)
				to -= 10
				continue
			#End of dbcheck
		#stopped
		cur.close()
		db.close()
		log.info('DBhandler stopped')
				
			
	def encodePacket(self, data):
		data = bencode.bencode(data)
		crc = crc32(str(data).encode())
		packet = '[GM]' + str(len(data)) + '|' + str(crc) + '|' + data + '[MG]'
		return str(packet).encode()
	
	def decodePacket(self, data):
		data = str(data, 'utf-8')
		if not (data[0:3] == '[GM]' or data[-4:-1] == '[MG]'):
			#Not for us probably...
			log.debug("Unknown or invalid packet: %s" % data)
			return None
		data = data[4:-4].split('|')
		if len(data) != 3:
			#Wrong packet size...
			log.debug("Wrong packet size: %s" % data)
			return None
		elif int(data[0]) != len(data[-1]):
			#Something went wrong, part of data is missing
			log.debug("Incomplete data: %s" % data)
			return None
		elif crc32(str(data[-1]).encode()) != data[1]:
			#Wrong crc
			log.debug("CRC Mismatch: %s" % data)
			return None
		else:
			#Good packet, decode
			try:
				pData = bencode.bdecode(data[-1])
			except bencode.BTFailure as e:
				log.debug("Bdecode failture: %s on packet %s" % (e, data))
				pData = None
			return pData
		#Never reached
		return
			
if __name__ == '__main__':
	#DO NOT START THIS ONE...
	raise Exception("Wrong file started. Use the start.py inside the base directory")